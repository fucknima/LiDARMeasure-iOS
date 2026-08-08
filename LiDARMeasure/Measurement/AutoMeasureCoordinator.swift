import ARKit
import Combine
import CoreVideo
import Foundation
import simd

/// 自动测量目标：检测目标或用户框选 ROI。
enum MeasureTarget {
    /// 分割检测目标（显式指定）。
    case detection(SegmentedObject)
    /// 显示空间归一化 ROI（左上原点，用户框选）。
    case roi(CGRect)
}

/// 自动测量编排器。
///
/// 自动模式流水线（任务书第 116 条）：
/// frame → VisionInferenceService(YOLO26m-seg) → ObjectTracker →
/// selected SegmentedObject → CoordinateMapper → DepthForeground →
/// PointCloudBuilder → GravityAlignedOBB → DimensionStabilizer → Quality
///
/// 框选模式：用户 ROI → Apple 前景实例分割 → 深度聚类 → 点云 → OBB。
@MainActor
final class AutoMeasureCoordinator: ObservableObject {
    struct PipelineDebug {
        var modelName = ""
        var detectorOn = false
        var objectCount = 0
        var selectedLabel: String?
        var selectedConfidence: Float?
        var selectedTrackID: String?
        var hasMask = false
        var maskCoverage: Float = 0
        var hasDepth = false
        var depthResolution = ""
        var validDepthRatio: Float = 0
        var rawPointCount = 0
        var filteredPointCount = 0
        var hasOBB = false
        var boxClipped = false
        var inferenceMs: Double = 0
        var thermalState = ""
    }

    let inferenceService: VisionInferenceService

    @Published private(set) var state: AutoMeasureState = .searching
    @Published private(set) var dimensions: MeasurementDimensions?
    @Published private(set) var detections: [SegmentedObject] = []
    @Published private(set) var tracks: [TrackedObject] = []
    @Published private(set) var selectedStableID: UUID?
    @Published private(set) var debug = PipelineDebug()
    @Published private(set) var quality: MeasurementQuality?
    @Published private(set) var lastOBB: GravityAlignedOBB?

    private var tracker = ObjectTracker()
    private var stabilizer = DimensionStabilizer()
    private var lastProcessTime: TimeInterval = 0
    private var processInterval: TimeInterval = 0.2
    private var trackingLimited = false
    private var threshold: Float = 0.3
    private var isProcessing = false
    private var lastInferenceMs: Double = 0
    private var thermalDowngrade = false

    init() {
        inferenceService = VisionInferenceService()
        debug.detectorOn = inferenceService.isAvailable
        debug.modelName = inferenceService.modelName
        if !inferenceService.isAvailable {
            state = .failed(.modelUnavailable)
        }
    }

    var selectedObject: SegmentedObject? {
        guard let id = selectedStableID else { return nil }
        return tracks.first { $0.stableID == id }?.object
    }

    // MARK: - 配置

    func reset() {
        tracker.clear()
        stabilizer.reset()
        lastProcessTime = 0
        isProcessing = false
        detections.removeAll()
        tracks.removeAll()
        selectedStableID = nil
        dimensions = nil
        quality = nil
        lastOBB = nil
        debug = PipelineDebug(
            modelName: inferenceService.modelName,
            detectorOn: inferenceService.isAvailable
        )
        state = inferenceService.isAvailable ? .searching : .failed(.modelUnavailable)
    }

    func setThreshold(_ value: Float) {
        threshold = value
    }

    func setTrackingLimited(_ value: Bool) {
        trackingLimited = value
    }

    /// 热降频：serious 时降频，critical 时暂停高频识别（任务书第 79/80 条）。
    func updateThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let name: String
        switch state {
        case .nominal: name = "nominal"
        case .fair: name = "fair"
        case .serious: name = "serious"
        case .critical: name = "critical"
        @unknown default: name = "unknown"
        }
        debug.thermalState = name
        if state == .serious {
            thermalDowngrade = true
            processInterval = 0.33
        } else if state == .critical {
            thermalDowngrade = true
            processInterval = 0.5
        } else {
            thermalDowngrade = false
            processInterval = 0.2
        }
    }

    // MARK: - 用户操作

    /// 用户点击选择目标：基于 stableID（任务书第 48/49 条）。
    func select(stableID: UUID?) {
        selectedStableID = stableID
        stabilizer.reset()
        state = .detected
    }

    /// 视图坐标点击 → 选择被点击的 track（无命中则清空选择）。
    func select(at viewPoint: CGPoint, geometry: FrameGeometry) {
        let modelPoint = CoordinateMapper.bottomLeftNormalized(
            viewPoint: viewPoint,
            transform: geometry.displayTransform
        )
        let hit = tracks.first { track in
            track.object.boundingBox.insetBy(dx: -0.02, dy: -0.02).contains(modelPoint)
        }
        select(stableID: hit?.stableID)
    }

    // MARK: - 主流程

    func process(frame: ARFrame, target: MeasureTarget?, viewSize: CGSize) async {
        guard inferenceService.isAvailable else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessTime >= processInterval, !isProcessing else { return }
        lastProcessTime = now
        isProcessing = true
        defer { isProcessing = false }

        updateThermalState()
        let geometry = FrameGeometry.make(frame: frame, viewportSize: viewSize)
        debug.depthResolution = "\(Int(geometry.depthResolution.width))x\(Int(geometry.depthResolution.height))"
        let pixelBuffer = frame.capturedImage

        // ---- 1. 检测 / 分割推理（自动模式；框选模式跳过 YOLO） ----
        var segmentedObjects: [SegmentedObject] = []
        var userROI: CGRect?
        var appleMask: CVPixelBuffer?

        switch target {
        case .detection(let object):
            segmentedObjects = [object]
        case .roi(let rect):
            userROI = rect
        case nil:
            let start = Date()
            guard let result = await inferenceService.infer(
                pixelBuffer: pixelBuffer,
                threshold: threshold
            ) else {
                return
            }
            lastInferenceMs = Date().timeIntervalSince(start) * 1000
            debug.inferenceMs = lastInferenceMs
            switch result {
            case .success(let objects):
                segmentedObjects = objects
            case .failure(let error):
                state = .failed(mapError(error))
                return
            }
        }

        // ---- 2. 跟踪（自动模式） ----
        if userROI == nil {
            tracks = tracker.update(detections: segmentedObjects)
            debug.objectCount = segmentedObjects.count
            detections = segmentedObjects
            if segmentedObjects.isEmpty {
                state = .searching
                return
            }
        }

        // ---- 3. 目标选择（自动模式） ----
        var targetObject: SegmentedObject?
        if let userROI {
            targetObject = nil
        } else if case .detection(let object) = target {
            targetObject = object
        } else if let id = selectedStableID, let tracked = tracker.trackedObject(stableID: id) {
            // 用户锁定目标优先级最高；只要还在就禁止自动换目标。
            targetObject = tracked.object
        } else {
            targetObject = bestCandidate(in: tracks.map(\.object))
        }
        guard let targetObject else {
            state = .detected
            return
        }
        selectedStableID = targetObject.stableID
        debug.selectedLabel = targetObject.label
        debug.selectedConfidence = targetObject.confidence
        debug.selectedTrackID = targetObject.stableID.uuidString.prefix(8).description

        // ---- 4. 目标完整性检查（自动模式） ----
        if userROI == nil, let failure = integrityFailure(targetObject.boundingBox) {
            state = .failed(failure)
            return
        }

        // ---- 5. 分割 mask：自动用 YOLO mask；框选用 Apple 前景实例 ----
        var mask = userROI == nil ? targetObject.mask : nil
        if let userROI, mask == nil {
            state = .segmenting
            mask = await inferenceService.allForegroundMask(pixelBuffer: pixelBuffer)
            if mask == nil {
                // 分割失败不致命：回退 ROI + 深度聚类（任务书第 43 条）。
                AppLog.vision.info("Box-select foreground mask unavailable, falling back to depth cluster")
            }
        } else {
            state = .segmenting
        }
        debug.hasMask = mask != nil
        debug.maskCoverage = targetObject.maskCoverage

        // ---- 6. 深度：YOLO mask 已存在时优先只统计 mask 内深度（任务书第 55 条） ----
        let roi = userROI ?? CoordinateMapper.displaySpace(bottomLeft: targetObject.boundingBox)
        state = .collectingDepth
        guard let band = foregroundBand(mask: mask, roi: roi, frame: frame) else {
            state = .failed(.noDepth)
            return
        }
        debug.hasDepth = true
        debug.validDepthRatio = band.validDepthRatio
        if band.validDepthRatio < 0.15 {
            state = .failed(.noDepth)
            return
        }

        // ---- 7. 点云（mask 内采样） ----
        let cloud = PointCloudBuilder.build(from: frame, configuration: .init(
            stride: 2,
            minimumConfidence: 0.5,
            depthBand: band.band,
            roi: roi,
            mask: mask
        ))
        debug.rawPointCount = cloud.points.count
        if cloud.points.count < 300 {
            state = .failed(.insufficientPoints)
            return
        }
        let filtered = BoundingBox3D.filterOutliers(cloud.points)
        debug.filteredPointCount = filtered.count

        // ---- 8. OBB ----
        guard let obb = GravityAlignedOBB.compute(of: filtered) else {
            state = .failed(.unstableGeometry)
            return
        }
        debug.hasOBB = true
        lastOBB = obb

        // ---- 9. 稳定与锁定（任务书第 68/69 条） ----
        dimensions = stabilizer.add(obb.dimensions)
        if stabilizer.isLocked {
            if let dims = dimensions, maxDrift(obb.dimensions, dims) < 0.08, !trackingLimited {
                state = .locked
            } else {
                stabilizer.reset()
                state = .measuring
            }
            quality = MeasurementQualityEvaluator.evaluate(
                trackingLimited: trackingLimited,
                depthConfidence: band.validDepthRatio,
                pointCount: cloud.points.count,
                distanceMeters: band.medianDepth,
                stability: 1
            )
        } else {
            state = stabilizer.stabilizationProgress > 0 ? .stabilizing : .measuring
        }
        if trackingLimited, state != .locked {
            state = .measuring
        }
    }

    // MARK: - 私有

    /// mask 内深度直方图优先；无 mask 时用 ROI 内直方图。
    private func foregroundBand(mask: CVPixelBuffer?, roi: CGRect, frame: ARFrame) -> DepthReader.ForegroundBand? {
        if let mask {
            return DepthReader.foregroundBand(in: roi, mask: mask, from: frame)
        }
        return DepthReader.foregroundBand(in: roi, from: frame)
    }

    /// 多目标选择：离屏幕中心近 + 框面积适中 + confidence 高（任务书第 44 条）。
    private func bestCandidate(in objects: [SegmentedObject]) -> SegmentedObject? {
        objects.min { a, b in
            score(a) < score(b)
        }
    }

    private func score(_ object: SegmentedObject) -> Float {
        let centerDistance = hypotf(
            Float(object.center.x - 0.5),
            Float(object.center.y - 0.5)
        )
        let area = Float(object.boundingBox.width * object.boundingBox.height)
        let areaPenalty = abs(area - 0.15) * 0.5
        return centerDistance * 2 + areaPenalty - object.confidence * 0.5
    }

    private func integrityFailure(_ box: CGRect) -> AutoMeasureError? {
        if box.width < 0.08 || box.height < 0.08 {
            return .objectTooSmall
        }
        let clipped = box.minX < 0.02 || box.minY < 0.02 || box.maxX > 0.98 || box.maxY > 0.98
        debug.boxClipped = clipped
        if clipped, state != .locked {
            return .objectClipped
        }
        return nil
    }

    private func maxDrift(_ a: MeasurementDimensions, _ b: MeasurementDimensions) -> Float {
        [
            abs(a.width - b.width) / max(a.width, Float.ulpOfOne),
            abs(a.height - b.height) / max(a.height, Float.ulpOfOne),
            abs(a.depth - b.depth) / max(a.depth, Float.ulpOfOne)
        ].max() ?? 0
    }

    private func mapError(_ error: Error) -> AutoMeasureError {
        if error is YOLO26SegDecoderError {
            return .modelOutputMismatch
        }
        return .inferenceFailed
    }
}

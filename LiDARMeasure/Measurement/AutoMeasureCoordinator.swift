import ARKit
import Combine
import CoreVideo
import Foundation
import simd

/// 自动测量目标：检测框或用户框选 ROI。
enum MeasureTarget {
    case detection(DetectedObject)
    /// 左上原点归一化 ROI（用户框选）。
    case roi(CGRect)
}

/// 自动测量编排器。
///
/// 流水线：CoreML 检测 → 目标选择/跟踪 → 实例分割匹配 → 深度直方图前景带
///        → ROI 点云 → 离群过滤 → 重力对齐 OBB → 时间稳定 → 状态机
///
/// 推理（检测/分割）在后台 actor 执行；点云与几何在主线程（数据量小，节流运行）。
@MainActor
final class AutoMeasureCoordinator: ObservableObject {
    struct PipelineDebug {
        var detectorOn = false
        var objectCount = 0
        var selectedLabel: String?
        var selectedConfidence: Float?
        var hasMask = false
        var hasDepth = false
        var validDepthRatio: Float = 0
        var pointCount = 0
        var hasOBB = false
        var boxClipped = false
    }

    let inferenceService: VisionInferenceService

    @Published private(set) var state: AutoMeasureState = .searching
    @Published private(set) var dimensions: MeasurementDimensions?
    @Published private(set) var detections: [DetectedObject] = []
    @Published private(set) var selectedObjectID: UUID?
    @Published private(set) var debug = PipelineDebug()
    @Published private(set) var quality: MeasurementQuality?
    @Published private(set) var lastOBB: GravityAlignedOBB?

    private var tracker = ObjectTracker()
    private var stabilizer = DimensionStabilizer()
    private var lastProcessTime: TimeInterval = 0
    private let processInterval: TimeInterval = 0.15
    private var trackingLimited = false
    private var threshold: Float = 0.35
    private var isProcessing = false

    init() {
        inferenceService = VisionInferenceService()
        debug.detectorOn = inferenceService.isAvailable
        if !inferenceService.isAvailable {
            state = .failed(.modelUnavailable)
        }
    }

    func reset() {
        tracker = ObjectTracker()
        stabilizer.reset()
        lastProcessTime = 0
        isProcessing = false
        detections.removeAll()
        selectedObjectID = nil
        dimensions = nil
        quality = nil
        lastOBB = nil
        debug = PipelineDebug(detectorOn: inferenceService.isAvailable)
        state = inferenceService.isAvailable ? .searching : .failed(.modelUnavailable)
    }

    func setThreshold(_ value: Float) {
        threshold = value
    }

    func setTrackingLimited(_ value: Bool) {
        trackingLimited = value
    }

    func select(objectID: UUID?) {
        selectedObjectID = objectID
        stabilizer.reset()
        state = .detected
    }

    /// 视图坐标点击 → 选择被点击的目标（无命中则清空选择）。
    func select(at viewPoint: CGPoint, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let normalized = CGPoint(x: viewPoint.x / viewSize.width, y: viewPoint.y / viewSize.height)
        let hit = detections.first { object in
            object.boundingBox.insetBy(dx: -0.02, dy: -0.02).contains(normalized)
        }
        select(objectID: hit?.id)
    }

    /// 处理一帧。target 为 nil 时使用当前跟踪中的目标。
    func process(frame: ARFrame, target: MeasureTarget?) async {
        guard inferenceService.isAvailable else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessTime >= processInterval, !isProcessing else { return }
        lastProcessTime = now
        isProcessing = true
        defer { isProcessing = false }

        let pixelBuffer = frame.capturedImage

        // 检测目标与 ROI。
        let detectionTarget: DetectedObject?
        let userROI: CGRect?
        switch target {
        case .detection(let object):
            detectionTarget = object
            userROI = nil
        case .roi(let rect):
            detectionTarget = nil
            userROI = rect
        case nil:
            detectionTarget = nil
            userROI = nil
        }

        // 1. 检测（后台推理）；框选模式跳过检测。
        if userROI == nil {
            guard let objects = await inferenceService.detect(
                pixelBuffer: pixelBuffer,
                threshold: threshold
            ) else {
                return
            }
            debug.objectCount = objects.count
            detections = objects
            if objects.isEmpty {
                state = .searching
                return
            }
        }

        // 2. 目标选择：显式目标 > 跨帧关联（保持 stableID）> 离屏幕中心最近。
        var targetObject: DetectedObject?
        if let detectionTarget {
            targetObject = detectionTarget
        } else if userROI == nil {
            let tracked = tracker.track(detections)
            if let selectedID = selectedObjectID,
               let byID = detections.first(where: { $0.id == selectedID }) {
                targetObject = byID
            } else {
                targetObject = tracked ?? detections.min { a, b in
                    centerDistance(a) < centerDistance(b)
                }
            }
        }
        if let targetObject {
            selectedObjectID = targetObject.id
            debug.selectedLabel = targetObject.label
            debug.selectedConfidence = targetObject.confidence
        }

        // 3. 目标完整性检查（仅检测目标）。
        if let targetObject, let failure = integrityFailure(targetObject.boundingBox) {
            state = .failed(failure)
            return
        }

        // 4. 实例分割匹配：检测目标匹配单实例；框选使用全前景掩码。
        var mask: CVPixelBuffer?
        if let targetObject {
            let segment = await inferenceService.segmentInstance(
                pixelBuffer: pixelBuffer,
                targetBox: targetObject.boundingBox,
                minimumIoU: 0.3
            )
            mask = segment?.mask
            debug.hasMask = mask != nil
        } else if let userROI {
            mask = await inferenceService.allForegroundMask(pixelBuffer: pixelBuffer)
            debug.hasMask = mask != nil
        }

        // 5. 深度直方图 + ROI 点云。
        let roi = userROI ?? (targetObject.map { VisionCoordinateMapper.topLeft($0.boundingBox) })
        guard let roi else {
            state = .searching
            return
        }
        guard let band = DepthReader.foregroundBand(in: roi, from: frame) else {
            state = .failed(.noDepth)
            return
        }
        debug.hasDepth = true
        debug.validDepthRatio = band.validDepthRatio
        if band.validDepthRatio < 0.15 {
            state = .failed(.noDepth)
            return
        }

        let cloud = PointCloudBuilder.build(from: frame, configuration: .init(
            stride: 2,
            minimumConfidence: 0.5,
            depthBand: band.band,
            roi: roi,
            mask: mask
        ))
        debug.pointCount = cloud.points.count
        if cloud.points.count < 300 {
            state = .failed(.insufficientPoints)
            return
        }
        let filtered = BoundingBox3D.filterOutliers(cloud.points)
        guard let obb = GravityAlignedOBB.compute(of: filtered) else {
            state = .failed(.unstableGeometry)
            return
        }
        debug.hasOBB = true
        lastOBB = obb

        // 6. 稳定与状态机。
        dimensions = stabilizer.add(obb.dimensions)
        if stabilizer.isLocked {
            state = .locked
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

    private func centerDistance(_ object: DetectedObject) -> CGFloat {
        hypot(object.center.x - 0.5, object.center.y - 0.5)
    }

    /// 目标框太小 / 触碰边缘 → 拒绝测量。
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
}

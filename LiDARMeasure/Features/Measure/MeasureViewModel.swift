import ARKit
import Combine
import Foundation
import RealityKit
import simd

@MainActor
final class MeasureViewModel: ObservableObject {
    let sessionManager = ARSessionManager()
    let roomPlanService = RoomPlanService()
    let historyStore = HistoryStore()
    let renderer = ARRenderer()

    @Published var unit: MeasurementUnit {
        didSet {
            UserDefaults.standard.set(unit.rawValue, forKey: "measurement.unit")
        }
    }

    @Published var mode: MeasurementMode = .automatic {
        didSet { modeDidChange(oldValue: oldValue) }
    }
    @Published private(set) var dimensions: MeasurementDimensions?
    @Published private(set) var distanceMeters: Float?
    @Published private(set) var quality: MeasurementQuality?
    @Published private(set) var statusText = "对准物体并保持手机稳定"
    @Published private(set) var detectionLabel: String?
    @Published private(set) var selectedPoints: [SIMD3<Float>] = []
    @Published private(set) var selectionRect: CGRect?
    @Published private(set) var pointCount = 0
    @Published private(set) var isSaving = false
    @Published var showDebugOverlay = false

    private let raycastService = RaycastService.self
    private let visionPipeline = VisionPipeline()
    private var smoother = MeasurementSmoother()
    private var dragStart: CGPoint?
    private var viewportSize: CGSize = .zero
    private var lastProcessTime: TimeInterval = 0
    private let processInterval: TimeInterval = 0.15

    var capabilities: DeviceCapabilities { sessionManager.capabilities }

    init() {
        let stored = UserDefaults.standard.string(forKey: "measurement.unit")
        unit = MeasurementUnit(rawValue: stored ?? "") ?? .centimeter
        sessionManager.frameHandler = { [weak self] frame in
            self?.process(frame: frame)
        }
        AppLog.measure.info("MeasureViewModel initialized")
    }

    var formattedDimensions: String? {
        dimensions?.formatted(using: unit)
    }

    var formattedDistance: String? {
        distanceMeters.map { unit.format($0) }
    }

    func setViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    // MARK: - 手动测量

    func handleTap(at location: CGPoint) {
        guard mode == .manualLength || mode == .manualDimensions else { return }
        guard let frame = sessionManager.lastFrame, let arView = sessionManager.arView else {
            statusText = "AR 尚未就绪"
            return
        }
        let point = raycastService.depthWorldPoint(at: location, in: arView, frame: frame)
            ?? raycastService.worldPoint(at: location, in: arView)
        guard let point else {
            statusText = "未找到可测量的表面，请对准平面"
            return
        }
        selectedPoints.append(point)

        if mode == .manualLength {
            if selectedPoints.count > 2 { selectedPoints.removeFirst() }
            if selectedPoints.count == 2 {
                distanceMeters = BoundingBox3D.distance(selectedPoints[0], selectedPoints[1])
                dimensions = nil
                renderer.showLine(from: selectedPoints[0], to: selectedPoints[1])
                statusText = "长度已计算"
                AppLog.measure.info("Manual length: \(self.distanceMeters!) m")
            } else {
                statusText = "已记录点 A，请点击点 B"
            }
        } else {
            if selectedPoints.count > 4 { selectedPoints.removeFirst() }
            if selectedPoints.count == 4 {
                let origin = selectedPoints[0]
                let width = BoundingBox3D.distance(origin, selectedPoints[1])
                let height = BoundingBox3D.distance(origin, selectedPoints[2])
                let depth = BoundingBox3D.distance(origin, selectedPoints[3])
                dimensions = MeasurementDimensions(width: width, height: height, depth: depth)
                distanceMeters = nil
                renderer.showPoints(selectedPoints, lines: [
                    (selectedPoints[0], selectedPoints[1]),
                    (selectedPoints[0], selectedPoints[2]),
                    (selectedPoints[0], selectedPoints[3])
                ])
                statusText = "长宽高已计算"
                AppLog.measure.info("Manual dimensions: \(width)m x \(height)m x \(depth)m")
            } else {
                statusText = "依次点击：左下、右下、左上、后角（\(selectedPoints.count)/4）"
            }
        }
    }

    // MARK: - 框选

    func beginSelection(at location: CGPoint) {
        guard mode == .boxSelection else { return }
        dragStart = location
        selectionRect = CGRect(origin: location, size: .zero)
    }

    func updateSelection(to location: CGPoint) {
        guard mode == .boxSelection, let dragStart else { return }
        selectionRect = CGRect(
            x: min(dragStart.x, location.x),
            y: min(dragStart.y, location.y),
            width: abs(location.x - dragStart.x),
            height: abs(location.y - dragStart.y)
        )
    }

    func endSelection() {
        guard let rect = selectionRect else { return }
        dragStart = nil
        if rect.width < 24 || rect.height < 24 {
            selectionRect = nil
            statusText = "框太小，请重新框选"
        } else {
            statusText = "已框选区域，保持手机稳定"
        }
    }

    // MARK: - 操作

    func undo() {
        if !selectedPoints.isEmpty {
            selectedPoints.removeLast()
            distanceMeters = nil
            if mode == .manualDimensions { dimensions = nil }
            renderer.clearAll()
        } else {
            clear()
        }
    }

    func clear() {
        selectedPoints.removeAll()
        distanceMeters = nil
        dimensions = nil
        detectionLabel = nil
        selectionRect = nil
        smoother.reset()
        pointCount = 0
        renderer.clearAll()
        statusText = "对准物体并保持手机稳定"
    }

    func save() async {
        guard distanceMeters != nil || dimensions != nil else {
            statusText = "还没有可保存的测量结果"
            return
        }
        isSaving = true
        defer { isSaving = false }

        var screenshotPath: String?
        if let image = ScreenshotService.captureWindow() {
            screenshotPath = ScreenshotService.saveToDocuments(image)
            do { try await ScreenshotService.saveToPhotos(image) }
            catch {
                AppLog.measure.error("Photo save skipped: \(error.localizedDescription, privacy: .public)")
            }
        }
        let record = MeasurementRecord(
            date: Date(),
            mode: mode,
            dimensions: dimensions ?? MeasurementDimensions(
                width: distanceMeters ?? 0, height: 0, depth: 0
            ),
            unit: unit,
            distanceMeters: distanceMeters,
            screenshotPath: screenshotPath,
            quality: quality?.grade.rawValue
        )
        historyStore.append(record)
        statusText = "已保存到测量历史"
        AppLog.measure.info("Measurement saved: \(record.primaryText)")
    }

    // MARK: - RoomPlan

    func startRoomScan() {
        guard mode == .roomScan else { return }
        roomPlanService.start()
        statusText = "正在扫描房间，缓慢移动手机"
    }

    func stopRoomScan() {
        roomPlanService.stop()
        if let first = roomPlanService.measurements.first {
            dimensions = first.dimensions
            statusText = "已识别物体：\(first.category)"
        } else {
            statusText = "房间扫描已停止"
        }
    }

    // MARK: - 内部

    private func modeDidChange(oldValue: MeasurementMode) {
        guard oldValue != mode else { return }
        clear()
        if oldValue == .roomScan {
            roomPlanService.stop()
            sessionManager.start()
        }
        if mode == .roomScan {
            sessionManager.pause()
            startRoomScan()
        }
        AppLog.measure.info("Mode changed: \(oldValue.rawValue) -> \(self.mode.rawValue)")
    }

    private func process(frame: ARFrame) {
        guard mode.usesPointCloud else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessTime >= processInterval else { return }
        lastProcessTime = now

        guard let sample = DepthReader.centerSample(from: frame) else {
            statusText = capabilities.sceneDepthAvailable
                ? "正在等待深度数据"
                : "当前设备不支持 LiDAR，自动三维测量受限"
            return
        }

        let vision = mode == .automatic ? visionPipeline.analyze(frame: frame) : nil
        if let observation = vision?.observation {
            detectionLabel = observation.identifier
        }

        let roi: CGRect?
        if mode == .boxSelection {
            roi = normalizedSelectionRect()
        } else if let box = vision?.observation?.boundingBox {
            // Vision 左下原点 → 深度图左上原点。
            roi = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        } else {
            roi = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        }
        guard let roi else {
            statusText = "请拖框选择物体"
            return
        }

        let tolerance: Float = sample.depth > 0.25 ? 0.1 : 0.05
        let band = max(0, sample.depth - tolerance)...(sample.depth + tolerance)
        let rawPoints = PointCloudBuilder.build(from: frame, configuration: .init(
            stride: 5,
            minimumConfidence: 0.5,
            depthBand: band,
            roi: roi,
            foregroundMask: vision?.foregroundMask
        ))
        let points = BoundingBox3D.filterOutliers(rawPoints)
        pointCount = points.count

        guard let box = BoundingBox3D.orientedBoundingBox(
            of: points.map(\.value),
            gravity: SIMD3(0, 1, 0)
        ) else {
            statusText = "有效点太少，请靠近物体或框选"
            quality = MeasurementQualityEvaluator.evaluate(
                trackingLimited: sessionManager.isTrackingLimited,
                depthConfidence: sample.confidence,
                pointCount: points.count,
                distanceMeters: sample.depth,
                stability: smoother.stabilityScore
            )
            return
        }

        dimensions = smoother.add(box.dimensions)
        statusText = smoother.isStable ? "测量稳定" : "请保持手机稳定"
        quality = MeasurementQualityEvaluator.evaluate(
            trackingLimited: sessionManager.isTrackingLimited,
            depthConfidence: sample.confidence,
            pointCount: points.count,
            distanceMeters: sample.depth,
            stability: smoother.stabilityScore
        )
        renderer.showBoundingBox(box)
    }

    private func normalizedSelectionRect() -> CGRect? {
        guard let rect = selectionRect,
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        return CGRect(
            x: rect.minX / viewportSize.width,
            y: rect.minY / viewportSize.height,
            width: rect.width / viewportSize.width,
            height: rect.height / viewportSize.height
        )
    }
}

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
    let autoCoordinator = AutoMeasureCoordinator()

    @Published var unit: MeasurementUnit {
        didSet {
            UserDefaults.standard.set(unit.rawValue, forKey: "measurement.unit")
        }
    }
    @Published var detectionThreshold: Float {
        didSet {
            UserDefaults.standard.set(detectionThreshold, forKey: "detection.threshold")
            autoCoordinator.setThreshold(detectionThreshold)
        }
    }
    @Published var mode: MeasurementMode = .automatic {
        didSet { modeDidChange(oldValue: oldValue) }
    }
    @Published private(set) var dimensions: MeasurementDimensions?
    @Published private(set) var distanceMeters: Float?
    @Published private(set) var quality: MeasurementQuality?
    @Published private(set) var manualStatusText = "对准物体并保持手机稳定"
    @Published private(set) var selectedPoints: [SIMD3<Float>] = []
    @Published private(set) var selectionRect: CGRect?
    @Published private(set) var pointCount = 0
    @Published private(set) var isSaving = false
    @Published var showDebugOverlay = false
    @Published var showCoordinateDebug = false

    private let raycastService = RaycastService.self
    private var dragStart: CGPoint?
    private var viewportSize: CGSize = .zero

    var capabilities: DeviceCapabilities { sessionManager.capabilities }

    /// 分割检测结果（模型空间左下原点归一化）。
    var detections: [SegmentedObject] { autoCoordinator.detections }
    var tracks: [TrackedObject] { autoCoordinator.tracks }
    var selectedStableID: UUID? { autoCoordinator.selectedStableID }
    var selectedObject: SegmentedObject? { autoCoordinator.selectedObject }
    var autoState: AutoMeasureState { autoCoordinator.state }
    var pipelineDebug: AutoMeasureCoordinator.PipelineDebug { autoCoordinator.debug }

    init() {
        let defaults = UserDefaults.standard
        unit = MeasurementUnit(rawValue: defaults.string(forKey: "measurement.unit") ?? "") ?? .centimeter
        let storedThreshold = defaults.float(forKey: "detection.threshold")
        detectionThreshold = storedThreshold > 0 ? storedThreshold : 0.30
        sessionManager.frameHandler = { [weak self] frame in
            self?.process(frame: frame)
        }
        autoCoordinator.setThreshold(detectionThreshold)
        AppLog.measure.info("MeasureViewModel initialized")
    }

    var formattedDimensions: String? {
        dimensions?.formatted(using: unit)
    }

    var formattedDistance: String? {
        distanceMeters.map { unit.format($0) }
    }

    /// 自动模式的用户可见状态文本。
    var autoStatusText: String {
        switch autoState {
        case .searching: return "未检测到支持的目标，可点击框选"
        case .detected: return "已识别目标，保持手机稳定"
        case .segmenting: return "正在分割目标…"
        case .collectingDepth: return "正在收集深度…"
        case .measuring: return "测量中…保持手机稳定"
        case .stabilizing: return "测量中…尺寸逐渐稳定"
        case .locked: return "测量已锁定"
        case .failed(let error): return error.message
        }
    }

    var statusText: String {
        if mode == .boxSelection, selectionRect == nil {
            return "请拖框选择物体"
        }
        return mode.usesPointCloud ? autoStatusText : manualStatusText
    }

    /// 当前可保存的尺寸（自动模式取协调器平滑结果，手动取本地结果）。
    var currentDimensionsForSave: MeasurementDimensions? {
        if mode.usesPointCloud {
            return autoCoordinator.dimensions
        }
        return dimensions
    }

    func setViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    // MARK: - 手动测量

    func handleTap(at location: CGPoint) {
        guard mode == .manualLength || mode == .manualDimensions else { return }
        guard let frame = sessionManager.lastFrame, let arView = sessionManager.arView else {
            manualStatusText = "AR 尚未就绪"
            return
        }
        let point = raycastService.depthWorldPoint(at: location, in: arView, frame: frame)
            ?? raycastService.worldPoint(at: location, in: arView)
        guard let point else {
            manualStatusText = "未找到可测量的表面，请对准平面"
            return
        }
        selectedPoints.append(point)

        if mode == .manualLength {
            if selectedPoints.count > 2 { selectedPoints.removeFirst() }
            if selectedPoints.count == 2 {
                distanceMeters = BoundingBox3D.distance(selectedPoints[0], selectedPoints[1])
                dimensions = nil
                renderer.showLine(from: selectedPoints[0], to: selectedPoints[1])
                manualStatusText = "长度已计算"
                AppLog.measure.info("Manual length: \(self.distanceMeters!) m")
            } else {
                manualStatusText = "已记录点 A，请点击点 B"
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
                manualStatusText = "长宽高已计算"
                AppLog.measure.info("Manual dimensions: \(width)m x \(height)m x \(depth)m")
            } else {
                manualStatusText = "依次点击：左下、右下、左上、后角（\(selectedPoints.count)/4）"
            }
        }
    }

    /// 点击选择自动模式目标（基于 stableID）。
    func selectAutoTarget(at location: CGPoint) {
        guard mode == .automatic else { return }
        guard let frame = sessionManager.lastFrame else { return }
        let geometry = FrameGeometry.make(frame: frame, viewportSize: viewportSize)
        autoCoordinator.select(at: location, geometry: geometry)
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
            manualStatusText = "框太小，请重新框选"
        } else {
            manualStatusText = "已框选区域，保持手机稳定"
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
        selectionRect = nil
        pointCount = 0
        renderer.clearAll()
        manualStatusText = "对准物体并保持手机稳定"
        if mode.usesPointCloud {
            autoCoordinator.reset()
        }
    }

    func save() async {
        let currentDimensions = currentDimensionsForSave
        guard distanceMeters != nil || currentDimensions != nil else {
            manualStatusText = "还没有可保存的测量结果"
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
            dimensions: currentDimensions ?? MeasurementDimensions(
                width: distanceMeters ?? 0, height: 0, depth: 0
            ),
            unit: unit,
            distanceMeters: distanceMeters,
            screenshotPath: screenshotPath,
            quality: quality?.grade.rawValue
        )
        historyStore.append(record)
        manualStatusText = "已保存到测量历史"
        AppLog.measure.info("Measurement saved: \(record.primaryText)")
    }

    // MARK: - RoomPlan

    func startRoomScan() {
        guard mode == .roomScan else { return }
        roomPlanService.start()
        manualStatusText = "正在扫描房间，缓慢移动手机"
    }

    func stopRoomScan() {
        roomPlanService.stop()
        if let first = roomPlanService.measurements.first {
            dimensions = first.dimensions
            manualStatusText = "已识别物体：\(first.category)"
        } else {
            manualStatusText = "房间扫描已停止"
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
        autoCoordinator.setTrackingLimited(sessionManager.isTrackingLimited)

        let target: MeasureTarget?
        if mode == .boxSelection {
            guard let rect = normalizedSelectionRect() else {
                autoCoordinator.reset()
                manualStatusText = "请拖框选择物体"
                return
            }
            target = .roi(rect)
        } else {
            target = nil
        }
        let viewSize = viewportSize
        Task { [weak self] in
            guard let self else { return }
            await self.autoCoordinator.process(frame: frame, target: target, viewSize: viewSize)
            self.pointCount = self.autoCoordinator.debug.filteredPointCount
            self.quality = self.autoCoordinator.quality
            if self.autoCoordinator.state == .locked, let dims = self.autoCoordinator.dimensions {
                self.dimensions = dims
            }
            if let obb = self.autoCoordinator.lastOBB {
                self.renderer.showBoundingBox(obb)
            }
        }
    }

    private func normalizedSelectionRect() -> CGRect? {
        guard let rect = selectionRect,
              viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        // 框选矩形 → 显示空间归一化（视图点 → displayTransform 反解）。
        guard let frame = sessionManager.lastFrame else { return nil }
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let topLeft = CoordinateMapper.displayNormalized(
            viewPoint: CGPoint(x: rect.minX, y: rect.minY),
            transform: transform
        )
        let bottomRight = CoordinateMapper.displayNormalized(
            viewPoint: CGPoint(x: rect.maxX, y: rect.maxY),
            transform: transform
        )
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }
}

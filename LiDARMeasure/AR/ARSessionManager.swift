import ARKit
import Combine
import Foundation
import RealityKit

@MainActor
final class ARSessionManager: NSObject, ObservableObject {
    let session = ARSession()
    let capabilities = CapabilityService.detect()

    @Published private(set) var trackingState = "未开始"
    @Published private(set) var isTrackingLimited = false
    @Published private(set) var lastFrame: ARFrame?
    @Published private(set) var depthAvailable = false
    @Published private(set) var lastError: String?

    weak var arView: ARView?
    var frameHandler: ((ARFrame) -> Void)?

    private var isRunning = false

    override init() {
        super.init()
        session.delegate = self
        AppLog.ar.info(
            "Capabilities: ar=\(capabilities.arKitAvailable), depth=\(capabilities.sceneDepthAvailable), smoothed=\(capabilities.smoothedSceneDepthAvailable), mesh=\(capabilities.meshReconstructionAvailable), roomPlan=\(capabilities.roomPlanAvailable)"
        )
    }

    func attach(to view: ARView) {
        arView = view
        view.session = session
        view.automaticallyConfigureSession = false
    }

    func start() {
        guard capabilities.arKitAvailable else {
            lastError = "当前设备不支持 ARKit"
            trackingState = "不可用"
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if capabilities.sceneDepthAvailable {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        if capabilities.smoothedSceneDepthAvailable {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        if capabilities.meshReconstructionAvailable {
            configuration.sceneReconstruction = .meshWithClassification
        }
        let options: ARSession.RunOptions = isRunning ? [] : [.resetTracking, .removeExistingAnchors]
        session.run(configuration, options: options)
        isRunning = true
        trackingState = "初始化中"
        lastError = nil
        AppLog.ar.info("AR session started")
    }

    func pause() {
        session.pause()
        isRunning = false
        trackingState = "已暂停"
        AppLog.ar.info("AR session paused")
    }
}

extension ARSessionManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.lastFrame = frame
            self.depthAvailable = frame.sceneDepth != nil || frame.smoothedSceneDepth != nil
            switch frame.camera.trackingState {
            case .normal:
                self.trackingState = "正常"
                self.isTrackingLimited = false
            case .limited(let reason):
                self.trackingState = "受限：\(String(describing: reason))"
                self.isTrackingLimited = true
            case .notAvailable:
                self.trackingState = "不可用"
                self.isTrackingLimited = true
            @unknown default:
                self.trackingState = "未知"
                self.isTrackingLimited = true
            }
            self.frameHandler?(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = "ARKit 失败：\(error.localizedDescription)"
            AppLog.ar.error("ARKit session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.trackingState = "被中断"
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.start()
        }
    }
}

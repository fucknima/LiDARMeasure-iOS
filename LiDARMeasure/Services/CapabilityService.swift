import ARKit
import Foundation
import RoomPlan

enum CapabilityService {
    /// 全部通过 API capability 检测，不通过机型判断。
    static func detect() -> DeviceCapabilities {
        let arAvailable = ARWorldTrackingConfiguration.isSupported
        let depth = arAvailable && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let smoothed = arAvailable && ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
        let mesh = arAvailable && ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
        let roomPlan = RoomCaptureSession.isSupported
        return DeviceCapabilities(
            arKitAvailable: arAvailable,
            lidarAvailable: depth,
            sceneDepthAvailable: depth,
            smoothedSceneDepthAvailable: smoothed,
            meshReconstructionAvailable: mesh,
            roomPlanAvailable: roomPlan
        )
    }
}

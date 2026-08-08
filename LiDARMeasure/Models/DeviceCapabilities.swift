import Foundation

struct DeviceCapabilities {
    var arKitAvailable: Bool
    var lidarAvailable: Bool
    var sceneDepthAvailable: Bool
    var smoothedSceneDepthAvailable: Bool
    var meshReconstructionAvailable: Bool
    var roomPlanAvailable: Bool

    var summary: [String] {
        [
            arKitAvailable ? "ARKit ✓" : "ARKit ✗",
            sceneDepthAvailable ? "SceneDepth ✓" : "SceneDepth ✗",
            smoothedSceneDepthAvailable ? "SmoothedDepth ✓" : "SmoothedDepth ✗",
            meshReconstructionAvailable ? "Mesh ✓" : "Mesh ✗",
            roomPlanAvailable ? "RoomPlan ✓" : "RoomPlan ✗"
        ]
    }
}

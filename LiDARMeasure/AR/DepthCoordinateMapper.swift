import ARKit
import CoreVideo
import Foundation
import simd

/// 深度像素 ↔ 相机坐标 ↔ 世界坐标。
///
/// 关键：camera.intrinsics 对应 capturedImage 分辨率，depthMap 分辨率更低，
/// 必须先按分辨率缩放 fx/fy/cx/cy，不能直接使用原始内参。
enum DepthCoordinateMapper {
    struct Geometry {
        let intrinsics: simd_float3x3
        let cameraTransform: simd_float4x4
        let cameraImageWidth: Float
        let cameraImageHeight: Float
        let depthMapWidth: Float
        let depthMapHeight: Float

        var scaleX: Float { cameraImageWidth / depthMapWidth }
        var scaleY: Float { cameraImageHeight / depthMapHeight }
    }

    static func geometry(frame: ARFrame, depthMap: CVPixelBuffer) -> Geometry {
        Geometry(
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            cameraImageWidth: Float(CVPixelBufferGetWidth(frame.capturedImage)),
            cameraImageHeight: Float(CVPixelBufferGetHeight(frame.capturedImage)),
            depthMapWidth: Float(CVPixelBufferGetWidth(depthMap)),
            depthMapHeight: Float(CVPixelBufferGetHeight(depthMap))
        )
    }

    /// 深度像素 (x, y) 与深度值 → 相机坐标。
    static func cameraPoint(x: Int, y: Int, depth: Float, geometry: Geometry) -> SIMD3<Float> {
        let fx = geometry.intrinsics.columns.0.x
        let fy = geometry.intrinsics.columns.1.y
        let cx = geometry.intrinsics.columns.2.x
        let cy = geometry.intrinsics.columns.2.y
        let u = Float(x) * geometry.scaleX
        let v = Float(y) * geometry.scaleY
        return SIMD3((u - cx) * depth / fx, (v - cy) * depth / fy, depth)
    }

    /// 深度像素 → 世界坐标。
    static func worldPoint(x: Int, y: Int, depth: Float, geometry: Geometry) -> SIMD3<Float> {
        let camera = cameraPoint(x: x, y: y, depth: depth, geometry: geometry)
        let world = geometry.cameraTransform * SIMD4(camera, 1)
        return SIMD3(world.x, world.y, world.z)
    }
}

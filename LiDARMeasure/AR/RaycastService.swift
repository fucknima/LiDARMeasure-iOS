import ARKit
import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// 屏幕点 → 世界坐标。
///
/// 优先使用深度图反投影（考虑 displayTransform 与相机内参），
/// 回退到平面 raycast，最后回退到相机高度水平面。
enum RaycastService {
    static func depthWorldPoint(
        at viewPoint: CGPoint,
        in arView: ARView,
        frame: ARFrame
    ) -> SIMD3<Float>? {
        guard let depthData = DepthReader.bestDepthData(from: frame) else { return nil }
        let map = depthData.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let size = arView.bounds.size
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return nil }

        // 视图归一化坐标 → 图像归一化坐标（displayTransform 是图像→视图，取逆）。
        let displayTransform = frame.displayTransform(for: .portrait, viewportSize: size)
        let viewToImage = displayTransform.inverted()
        let normalizedView = CGPoint(x: viewPoint.x / size.width, y: viewPoint.y / size.height)
        let normalizedImage = normalizedView.applying(viewToImage)
        let px = Int(normalizedImage.x * CGFloat(width))
        let py = Int(normalizedImage.y * CGFloat(height))
        guard px >= 0, px < width, py >= 0, py < height else { return nil }

        // 3x3 邻域取中位数深度，降低单像素噪声。
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        var candidates: [Float] = []
        for y in max(0, py - 1)...min(height - 1, py + 1) {
            for x in max(0, px - 1)...min(width - 1, px + 1) {
                let depth = values[y * rowStride + x]
                if depth.isFinite, depth > 0 { candidates.append(depth) }
            }
        }
        guard let depth = RobustStatistics.median(candidates) else { return nil }

        // 深度像素 → 相机坐标（内参缩放） → 世界坐标。
        let cameraImageWidth = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let cameraImageHeight = Float(CVPixelBufferGetHeight(frame.capturedImage))
        let intrinsics = frame.camera.intrinsics
        let scaleX = cameraImageWidth / Float(width)
        let scaleY = cameraImageHeight / Float(height)
        let cameraPoint = SIMD3<Float>(
            (Float(px) * scaleX - intrinsics.columns.2.x) / intrinsics.columns.0.x,
            (Float(py) * scaleY - intrinsics.columns.2.y) / intrinsics.columns.1.y,
            1
        ) * depth
        let world = frame.camera.transform * SIMD4(cameraPoint, 1)
        return SIMD3(world.x, world.y, world.z)
    }

    static func worldPoint(at viewPoint: CGPoint, in arView: ARView) -> SIMD3<Float>? {
        guard let ray = arView.ray(through: viewPoint) else { return nil }
        for target in [ARRaycastQuery.Target.estimatedPlane, .existingPlaneGeometry] {
            let query = ARRaycastQuery(
                origin: ray.origin,
                direction: ray.direction,
                allowing: target,
                alignment: .any
            )
            if let result = arView.session.raycast(query).first {
                return SIMD3(
                    result.worldTransform.columns.3.x,
                    result.worldTransform.columns.3.y,
                    result.worldTransform.columns.3.z
                )
            }
        }
        // 回退：与相机高度水平面求交。
        guard ray.direction.y < -0.001 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        guard t > 0, t.isFinite else { return nil }
        return ray.origin + ray.direction * t
    }
}

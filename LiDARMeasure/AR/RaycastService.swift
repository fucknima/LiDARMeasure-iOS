import ARKit
import CoreGraphics
import Foundation
import RealityKit
import UIKit

/// 屏幕点 → 世界坐标。
///
/// 优先使用深度图反投影（经 CoordinateMapper 统一坐标映射），
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

        // 视图点 → 显示归一化（displayTransform 反解 + 原点翻转）。
        let transform = frame.displayTransform(for: .portrait, viewportSize: size)
        let displayPoint = CoordinateMapper.displayNormalized(viewPoint: viewPoint, transform: transform)
        let depthSize = CGSize(width: width, height: height)
        let pixel = CoordinateMapper.depthPixel(normalized: displayPoint, depthSize: depthSize)

        // 3x3 邻域取中位数深度，降低单像素噪声。
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        var candidates: [Float] = []
        for y in max(0, pixel.y - 1)...min(height - 1, pixel.y + 1) {
            for x in max(0, pixel.x - 1)...min(width - 1, pixel.x + 1) {
                let depth = values[y * rowStride + x]
                if depth.isFinite, depth > 0 { candidates.append(depth) }
            }
        }
        guard let depth = RobustStatistics.median(candidates) else { return nil }

        // 深度像素 → 相机坐标（内参缩放） → 世界坐标。
        let geometry = DepthCoordinateMapper.geometry(frame: frame, depthMap: map)
        let world = DepthCoordinateMapper.worldPoint(x: pixel.x, y: pixel.y, depth: depth, geometry: geometry)
        return world
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

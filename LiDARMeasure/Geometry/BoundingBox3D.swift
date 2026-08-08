import Accelerate
import Foundation
import simd

/// 三维几何基础工具：距离、AABB、MAD 离群过滤、均值（Accelerate vDSP）。
/// OBB 由 GravityAlignedOBB 提供。
enum BoundingBox3D {
    static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(a, b)
    }

    /// 世界轴对齐包围盒，用于调试对比。
    static func axisAlignedDimensions(of points: [SIMD3<Float>]) -> MeasurementDimensions? {
        let valid = points.filter(\.isFinite)
        guard let first = valid.first else { return nil }
        var minValue = first
        var maxValue = first
        for point in valid.dropFirst() {
            minValue = simd_min(minValue, point)
            maxValue = simd_max(maxValue, point)
        }
        let size = maxValue - minValue
        return MeasurementDimensions(width: abs(size.x), height: abs(size.y), depth: abs(size.z))
    }

    /// 基于到点云中心的距离做 MAD 离群过滤。
    static func filterOutliers(_ points: [SIMD3<Float>], multiplier: Float = 3) -> [SIMD3<Float>] {
        let valid = points.filter(\.isFinite)
        guard valid.count >= 8 else { return valid }
        let center = mean(of: valid)
        let distances = valid.map { simd_distance($0, center) }
        guard let median = RobustStatistics.median(distances),
              let mad = RobustStatistics.mad(distances),
              mad > Float.ulpOfOne else { return valid }
        let limit = median + multiplier * 1.4826 * mad
        return valid.filter { simd_distance($0, center) <= limit }
    }

    static func mean(of points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var xs = [Float](repeating: 0, count: points.count)
        var ys = [Float](repeating: 0, count: points.count)
        var zs = [Float](repeating: 0, count: points.count)
        for (index, point) in points.enumerated() {
            xs[index] = point.x
            ys[index] = point.y
            zs[index] = point.z
        }
        var meanX: Float = 0
        var meanY: Float = 0
        var meanZ: Float = 0
        let length = vDSP_Length(points.count)
        vDSP_meanv(xs, 1, &meanX, length)
        vDSP_meanv(ys, 1, &meanY, length)
        vDSP_meanv(zs, 1, &meanZ, length)
        return SIMD3(meanX, meanY, meanZ)
    }
}

extension SIMD3 where Scalar == Float {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

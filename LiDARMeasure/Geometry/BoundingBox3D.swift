import Accelerate
import Foundation
import simd

struct OrientedBoundingBox {
    var center: SIMD3<Float>
    var axes: simd_float3x3
    var dimensions: MeasurementDimensions
    var corners: [SIMD3<Float>]

    var transform: simd_float4x4 {
        var value = matrix_identity_float4x4
        value.columns.0 = SIMD4(axes.columns.0, 0)
        value.columns.1 = SIMD4(axes.columns.1, 0)
        value.columns.2 = SIMD4(axes.columns.2, 0)
        value.columns.3 = SIMD4(center, 1)
        return value
    }
}

/// 三维几何：距离、AABB、OBB（重力对齐 + 水平面 2D PCA 闭式解）。
///
/// 协方差 2x2 的特征方向存在解析角度，避免自造特征值求解器；
/// 中心点计算使用 Accelerate vDSP。
enum BoundingBox3D {
    static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(a, b)
    }

    /// 只按世界轴对齐的包围盒，用于调试对比。
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
    static func filterOutliers(_ points: [Point3D], multiplier: Float = 3) -> [Point3D] {
        let valid = points.filter { $0.value.isFinite }
        guard valid.count >= 8 else { return valid }
        let center = mean(of: valid.map(\.value))
        let distances = valid.map { simd_distance($0.value, center) }
        guard let median = RobustStatistics.median(distances),
              let mad = RobustStatistics.mad(distances),
              mad > Float.ulpOfOne else { return valid }
        let limit = median + multiplier * 1.4826 * mad
        return valid.filter { simd_distance($0.value, center) <= limit }
    }

    /// 重力对齐 OBB：Y 轴固定为重力方向，水平两轴由 2D PCA 闭式解得到。
    static func orientedBoundingBox(
        of points: [SIMD3<Float>],
        gravity: SIMD3<Float> = SIMD3(0, 1, 0)
    ) -> OrientedBoundingBox? {
        let valid = points.filter(\.isFinite)
        guard valid.count >= 4 else { return nil }

        let center = mean(of: valid)
        let up = normalized(gravity, fallback: SIMD3(0, 1, 0))
        let worldZ = SIMD3<Float>(0, 0, 1)
        let worldX = SIMD3<Float>(1, 0, 0)
        let reference = abs(simd_dot(up, worldZ)) > 0.9 ? worldX : worldZ
        let projected = reference - up * simd_dot(reference, up)
        let forward = normalized(projected, fallback: worldZ)
        let right = normalized(simd_cross(up, forward), fallback: worldX)

        var covarianceXX: Float = 0
        var covarianceXZ: Float = 0
        var covarianceZZ: Float = 0
        for point in valid {
            let delta = point - center
            let x = simd_dot(delta, right)
            let z = simd_dot(delta, forward)
            covarianceXX += x * x
            covarianceXZ += x * z
            covarianceZZ += z * z
        }
        let angle = 0.5 * atan2(2 * covarianceXZ, covarianceXX - covarianceZZ)
        let rotatedA = normalized(right * cos(angle) + forward * sin(angle), fallback: right)
        let rotatedB = normalized(simd_cross(up, rotatedA), fallback: forward)
        let axes = simd_float3x3(columns: (rotatedA, up, rotatedB))

        var minProjection = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxProjection = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for point in valid {
            let delta = point - center
            let projection = SIMD3(
                simd_dot(delta, rotatedA),
                simd_dot(delta, up),
                simd_dot(delta, rotatedB)
            )
            minProjection = simd_min(minProjection, projection)
            maxProjection = simd_max(maxProjection, projection)
        }

        let dimensions = MeasurementDimensions(
            width: maxProjection.x - minProjection.x,
            height: maxProjection.y - minProjection.y,
            depth: maxProjection.z - minProjection.z
        )
        let localCenter = (minProjection + maxProjection) * 0.5
        let worldCenter = center + axes * localCenter
        let corners = cornerPoints(center: worldCenter, axes: axes, dimensions: dimensions)
        return OrientedBoundingBox(
            center: worldCenter,
            axes: axes,
            dimensions: dimensions,
            corners: corners
        )
    }

    static func cornerPoints(
        center: SIMD3<Float>,
        axes: simd_float3x3,
        dimensions: MeasurementDimensions
    ) -> [SIMD3<Float>] {
        let half = SIMD3<Float>(dimensions.width, dimensions.height, dimensions.depth) * 0.5
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(8)
        for y in [-1, 1] as [Float] {
            for x in [-1, 1] as [Float] {
                for z in [-1, 1] as [Float] {
                    result.append(center + axes * (SIMD3(x, y, z) * half))
                }
            }
        }
        return result
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

    private static func normalized(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > Float.ulpOfOne && length.isFinite ? value / length : fallback
    }
}

private extension SIMD3 where Scalar == Float {
    var isFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}

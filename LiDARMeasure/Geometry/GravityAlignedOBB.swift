import Foundation
import simd

/// 閲嶅姏瀵归綈 OBB銆?///
/// - 楂?= 閲嶅姏鏂瑰悜锛圷锛夌殑 percentile 鑼冨洿
/// - 闀?/ 瀹?= 姘村钩闈紙XZ锛?D PCA 涓昏酱锛岄暱 = 姘村钩杈冮暱杈?/// - percentile 瑁佸壀锛堥粯璁?1%~99%锛夐槻姝㈢缇ょ偣鎶婂昂瀵告媺澶?struct GravityAlignedOBB {
    var center: SIMD3<Float>
    var axes: simd_float3x3
    /// width = 姘村钩杈冪煭杈癸紝height = 鍨傜洿楂橈紝depth = 姘村钩杈冮暱杈广€?    var dimensions: MeasurementDimensions
    var corners: [SIMD3<Float>]

    static func compute(
        of points: [SIMD3<Float>],
        gravity: SIMD3<Float> = SIMD3(0, 1, 0),
        lowerPercentile: Float = 0.01,
        upperPercentile: Float = 0.99
    ) -> GravityAlignedOBB? {
        let valid = points.filter { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
        guard valid.count >= 8 else { return nil }
        // MAD 棰勮繃婊わ細绂荤兢鐐逛細姹℃煋 PCA 涓昏酱鏂瑰悜锛屽繀椤诲厛鍓旈櫎锛堜换鍔′功绗?37 鏉★級銆?        let cleaned = filterOutliersByDistance(valid)
        guard cleaned.count >= 8 else { return nil }

        let up = normalized(gravity, fallback: SIMD3(0, 1, 0))
        let worldZ = SIMD3<Float>(0, 0, 1)
        let worldX = SIMD3<Float>(1, 0, 0)
        let reference = abs(simd_dot(up, worldZ)) > 0.9 ? worldX : worldZ
        let projected = reference - up * simd_dot(reference, up)
        let forward = normalized(projected, fallback: worldZ)
        let right = normalized(simd_cross(up, forward), fallback: worldX)

        let yValues = cleaned.map(\.y)
        let heightMin = percentile(yValues, fraction: lowerPercentile) ?? yValues.min() ?? 0
        let heightMax = percentile(yValues, fraction: upperPercentile) ?? yValues.max() ?? 0
        let height = max(0, heightMax - heightMin)

        // 姘村钩闈㈡姇褰?鈫?2D PCA銆?        let horizontal = cleaned.map { point -> SIMD2<Float> in
            let delta = point - SIMD3(0, heightMin, 0)
            return SIMD2(simd_dot(delta, right), simd_dot(delta, forward))
        }
        guard let pca = PCA2D.principalAxes(of: horizontal) else { return nil }

        let horizontalA = SIMD3<Float>(pca.primary.x, 0, pca.primary.y)
        let horizontalB = SIMD3<Float>(pca.secondary.x, 0, pca.secondary.y)
        let axes = simd_float3x3(columns: (horizontalA, up, horizontalB))

        let projections = horizontal.map { point in
            SIMD2(simd_dot(point, pca.primary), simd_dot(point, pca.secondary))
        }
        let aMin = percentile(projections.map(\.x), fraction: lowerPercentile) ?? projections.map(\.x).min() ?? 0
        let aMax = percentile(projections.map(\.x), fraction: upperPercentile) ?? projections.map(\.x).max() ?? 0
        let bMin = percentile(projections.map(\.y), fraction: lowerPercentile) ?? projections.map(\.y).min() ?? 0
        let bMax = percentile(projections.map(\.y), fraction: upperPercentile) ?? projections.map(\.y).max() ?? 0
        let extentA = max(0, aMax - aMin)
        let extentB = max(0, bMax - bMin)

        // 闀?= 姘村钩杈冮暱杈广€?        let lengthAxis = extentA >= extentB ? horizontalA : horizontalB
        let widthAxis = extentA >= extentB ? horizontalB : horizontalA
        let length = max(extentA, extentB)
        let width = min(extentA, extentB)
        let finalAxes = simd_float3x3(columns: (widthAxis, up, lengthAxis))

        let centerA = (aMin + aMax) / 2
        let centerB = (bMin + bMax) / 2
        let heightCenter = (heightMin + heightMax) / 2
        let center = horizontalA * (extentA >= extentB ? centerA : centerB)
            + horizontalB * (extentA >= extentB ? centerB : centerA)
            + up * heightCenter

        let dimensions = MeasurementDimensions(width: width, height: height, depth: length)
        let corners = cornerPoints(center: center, axes: finalAxes, dimensions: dimensions)
        return GravityAlignedOBB(center: center, axes: finalAxes, dimensions: dimensions, corners: corners)
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

    private static func percentile(_ values: [Float], fraction: Float) -> Float? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let fraction = min(1, max(0, fraction))
        let index = Int(floor(Float(sorted.count - 1) * fraction))
        return sorted[index]
    }

    /// 基于到点云中心距离的 MAD 离群过滤，防止离群点污染 PCA 主轴。
    static func filterOutliersByDistance(_ points: [SIMD3<Float>], multiplier: Float = 3) -> [SIMD3<Float>] {
        guard points.count >= 8 else { return points }
        let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let distances = points.map { simd_distance($0, center) }
        guard let median = RobustStatistics.median(distances),
              let mad = RobustStatistics.mad(distances),
              mad > Float.ulpOfOne else { return points }
        let limit = median + multiplier * 1.4826 * mad
        return points.filter { simd_distance($0, center) <= limit }
    }

    private static func normalized(_ value: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let length = simd_length(value)
        return length > Float.ulpOfOne && length.isFinite ? value / length : fallback
    }
}


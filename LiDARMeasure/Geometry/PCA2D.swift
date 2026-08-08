import Foundation
import simd

/// 2D 主成分分析（对称 2x2 协方差闭式解，无需特征值求解器）。
enum PCA2D {
    struct Result {
        /// 主轴单位向量（方差最大方向）。
        var primary: SIMD2<Float>
        /// 次轴单位向量（与主轴正交）。
        var secondary: SIMD2<Float>
        /// 主轴投影方差。
        var primaryVariance: Float
        /// 次轴投影方差。
        var secondaryVariance: Float
    }

    static func principalAxes(of points: [SIMD2<Float>]) -> Result? {
        let valid = points.filter { $0.x.isFinite && $0.y.isFinite }
        guard valid.count >= 3 else { return nil }
        let center = valid.reduce(SIMD2<Float>.zero, +) / Float(valid.count)

        var xx: Float = 0
        var xy: Float = 0
        var yy: Float = 0
        for point in valid {
            let delta = point - center
            xx += delta.x * delta.x
            xy += delta.x * delta.y
            yy += delta.y * delta.y
        }

        let angle = 0.5 * atan2(2 * xy, xx - yy)
        let primary = SIMD2(cos(angle), sin(angle))
        let secondary = SIMD2(-sin(angle), cos(angle))
        let primaryVariance = xx * cos(angle) * cos(angle)
            + 2 * xy * cos(angle) * sin(angle)
            + yy * sin(angle) * sin(angle)
        let secondaryVariance = xx * sin(angle) * sin(angle)
            - 2 * xy * cos(angle) * sin(angle)
            + yy * cos(angle) * cos(angle)
        return Result(
            primary: primary,
            secondary: secondary,
            primaryVariance: primaryVariance / Float(valid.count),
            secondaryVariance: secondaryVariance / Float(valid.count)
        )
    }
}

import Foundation

/// 稳健统计：均值、中位数、MAD、IQR，用于深度/点云离群过滤。
enum RobustStatistics {
    static func finiteValues(_ values: [Float]) -> [Float] {
        values.filter { $0.isFinite }
    }

    static func mean(_ values: [Float]) -> Float? {
        let values = finiteValues(values)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    static func median(_ values: [Float]) -> Float? {
        let values = finiteValues(values).sorted()
        guard !values.isEmpty else { return nil }
        if values.count.isMultiple(of: 2) {
            return (values[values.count / 2 - 1] + values[values.count / 2]) / 2
        }
        return values[values.count / 2]
    }

    static func mad(_ values: [Float]) -> Float? {
        guard let center = median(values) else { return nil }
        return median(finiteValues(values).map { abs($0 - center) })
    }

    /// 中位数 + 修正 MAD 过滤，multiplier 默认 3。
    static func filterByMAD(_ values: [Float], multiplier: Float = 3) -> [Float] {
        let values = finiteValues(values)
        guard let center = median(values), let deviation = mad(values), deviation > Float.ulpOfOne else {
            return values
        }
        let limit = multiplier * 1.4826 * deviation
        return values.filter { abs($0 - center) <= limit }
    }

    /// IQR 过滤，multiplier 默认 1.5。
    static func filterByIQR(_ values: [Float], multiplier: Float = 1.5) -> [Float] {
        let values = finiteValues(values).sorted()
        guard values.count >= 4 else { return values }
        let quarter = values.count / 4
        let lower = values[quarter]
        let upper = values[values.count - 1 - quarter]
        let spread = (upper - lower) * multiplier
        return values.filter { $0 >= lower - spread && $0 <= upper + spread }
    }
}

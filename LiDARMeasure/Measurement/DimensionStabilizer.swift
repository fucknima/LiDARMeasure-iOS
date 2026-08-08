import Foundation

/// 尺寸时间平滑与稳定判定：
/// - 保存最近 windowSize 帧，各维取中位数
/// - 最近样本与中位数每维相对变化 < 3% 且持续 lockFrameCount 帧 → 锁定
struct DimensionStabilizer {
    let windowSize: Int
    let stableThreshold: Float
    let lockFrameCount: Int

    private var samples: [MeasurementDimensions] = []
    private var stableStreak = 0

    init(windowSize: Int = 12, stableThreshold: Float = 0.03, lockFrameCount: Int = 8) {
        self.windowSize = windowSize
        self.stableThreshold = stableThreshold
        self.lockFrameCount = lockFrameCount
    }

    /// 中位数平滑后的当前尺寸。
    var current: MeasurementDimensions? {
        guard !samples.isEmpty else { return nil }
        return MeasurementDimensions(
            width: RobustStatistics.median(samples.map(\.width)) ?? 0,
            height: RobustStatistics.median(samples.map(\.height)) ?? 0,
            depth: RobustStatistics.median(samples.map(\.depth)) ?? 0
        )
    }

    var isLocked: Bool { stableStreak >= lockFrameCount }

    @discardableResult
    mutating func add(_ dimensions: MeasurementDimensions) -> MeasurementDimensions {
        samples.append(dimensions)
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        if let current {
            let maxDrift = [
                abs(current.width - dimensions.width) / max(current.width, Float.ulpOfOne),
                abs(current.height - dimensions.height) / max(current.height, Float.ulpOfOne),
                abs(current.depth - dimensions.depth) / max(current.depth, Float.ulpOfOne)
            ].max() ?? 0
            stableStreak = maxDrift < stableThreshold ? stableStreak + 1 : 0
        }
        return current ?? dimensions
    }

    mutating func reset() {
        samples.removeAll()
        stableStreak = 0
    }
}

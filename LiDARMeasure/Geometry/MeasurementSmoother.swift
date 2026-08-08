import Foundation

/// 自动测量稳定器：保留最近 N 帧尺寸，取中位数；变化 < 2% 且持续若干帧判定稳定。
struct MeasurementSmoother {
    let windowSize: Int
    let relativeTolerance: Float
    let stableFrameCount: Int

    private var samples: [MeasurementDimensions] = []
    private var stableStreak = 0

    init(windowSize: Int = 15, relativeTolerance: Float = 0.02, stableFrameCount: Int = 5) {
        self.windowSize = windowSize
        self.relativeTolerance = relativeTolerance
        self.stableFrameCount = stableFrameCount
    }

    var current: MeasurementDimensions? {
        guard !samples.isEmpty else { return nil }
        return MeasurementDimensions(
            width: RobustStatistics.median(samples.map(\.width)) ?? 0,
            height: RobustStatistics.median(samples.map(\.height)) ?? 0,
            depth: RobustStatistics.median(samples.map(\.depth)) ?? 0
        )
    }

    var isStable: Bool { stableStreak >= stableFrameCount }

    /// 0...1，1 表示完全稳定。
    var stabilityScore: Float {
        guard samples.count >= 3 else { return 0 }
        let maxSpread = [
            relativeSpread(of: samples.map(\.width)),
            relativeSpread(of: samples.map(\.height)),
            relativeSpread(of: samples.map(\.depth))
        ].max() ?? 0
        guard maxSpread > 0 else { return 1 }
        return min(1, max(0, 1 - maxSpread / relativeTolerance))
    }

    @discardableResult
    mutating func add(_ dimensions: MeasurementDimensions) -> MeasurementDimensions {
        samples.append(dimensions)
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        if let current {
            let drift = maxDrift(from: current, to: dimensions)
            stableStreak = drift <= relativeTolerance ? stableStreak + 1 : 0
        }
        return current ?? dimensions
    }

    mutating func reset() {
        samples.removeAll()
        stableStreak = 0
    }

    private func maxDrift(from a: MeasurementDimensions, to b: MeasurementDimensions) -> Float {
        [
            abs(a.width - b.width) / max(a.width, Float.ulpOfOne),
            abs(a.height - b.height) / max(a.height, Float.ulpOfOne),
            abs(a.depth - b.depth) / max(a.depth, Float.ulpOfOne)
        ].max() ?? 0
    }

    private func relativeSpread(of values: [Float]) -> Float {
        guard let median = RobustStatistics.median(values) else { return 0 }
        let deviations = values.map { abs($0 - median) }
        return RobustStatistics.median(deviations) ?? 0
    }
}

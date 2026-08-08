import ARKit
import CoreVideo
import Foundation

/// 读取 ARKit 场景深度：优先 smoothedSceneDepth，回退 sceneDepth。
enum DepthReader {
    struct Sample {
        let depth: Float
        let confidence: Float
    }

    /// ROI 深度分析结果：前景深度带 + 深度有效率。
    struct ForegroundBand {
        let band: ClosedRange<Float>
        let validDepthRatio: Float
        let medianDepth: Float
    }

    static func bestDepthData(from frame: ARFrame) -> ARDepthData? {
        frame.smoothedSceneDepth ?? frame.sceneDepth
    }

    /// 准星附近（默认 7x7）采样深度，过滤无效值与低置信度，取深度中位数。
    static func centerSample(from frame: ARFrame, radius: Int = 3) -> Sample? {
        guard let data = bestDepthData(from: frame) else { return nil }
        let map = data.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let confidenceMap = data.confidenceMap
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        let confidenceValues = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        var depths: [Float] = []
        var confidences: [Float] = []
        let cx = width / 2
        let cy = height / 2
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) {
                let depth = values[y * rowStride + x]
                guard depth.isFinite, depth > 0 else { continue }
                // ARKit confidence：0 低 ~ 2 高。
                let confidence: Float
                if let confidenceValues {
                    confidence = Float(confidenceValues[y * confidenceStride + x]) / 2
                } else {
                    confidence = 1
                }
                guard confidence >= 0.5 else { continue }
                depths.append(depth)
                confidences.append(confidence)
            }
        }
        guard let median = RobustStatistics.median(depths) else { return nil }
        let meanConfidence = RobustStatistics.mean(confidences) ?? 1
        return Sample(depth: median, confidence: meanConfidence)
    }

    /// ROI 内深度直方图 → 前景深度带。
    ///
    /// - roi：左上原点归一化
    /// - 用直方图 dominant peak 定位前景深度峰，tolerance 由峰宽度动态确定，
    ///   不固定死 ±10cm；同时统计深度有效率 validDepthRatio
    static func foregroundBand(
        in roi: CGRect,
        from frame: ARFrame,
        stride: Int = 2
    ) -> ForegroundBand? {
        guard let data = bestDepthData(from: frame) else { return nil }
        let map = data.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let confidenceMap = data.confidenceMap
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
        }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        let confidenceValues = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        var validCount = 0
        var totalCount = 0
        var depths: [Float] = []

        let xRange = Int(roi.minX * CGFloat(width))..<Int(roi.maxX * CGFloat(width))
        let yRange = Int(roi.minY * CGFloat(height))..<Int(roi.maxY * CGFloat(height))
        guard !xRange.isEmpty, !yRange.isEmpty else { return nil }

        for y in yRange where y >= 0 && y < height {
            for x in xRange where x >= 0 && x < width {
                totalCount += 1
                let depth = values[y * rowStride + x]
                guard depth.isFinite, depth > 0 else { continue }
                let confidence: Float
                if let confidenceValues {
                    confidence = Float(confidenceValues[y * confidenceStride + x]) / 2
                } else {
                    confidence = 1
                }
                guard confidence >= 0.5 else { continue }
                validCount += 1
                depths.append(depth)
            }
        }
        guard totalCount > 0 else { return nil }
        let validRatio = Float(validCount) / Float(totalCount)
        guard validCount >= 40, let histogram = depthHistogram(depths, binCount: 32) else {
            return nil
        }

        // 取 dominant peak 及其相邻 bin 合并，中位数作为前景中心。
        var peakIndex = 0
        for index in histogram.bins.indices where histogram.bins[index] > histogram.bins[peakIndex] {
            peakIndex = index
        }
        let lowerIndex = max(0, peakIndex - 1)
        let upperIndex = min(histogram.bins.count - 1, peakIndex + 1)
        let bandDepths = depths.filter {
            $0 >= histogram.binRanges[lowerIndex].lowerBound
                && $0 <= histogram.binRanges[upperIndex].upperBound
        }
        guard let medianDepth = RobustStatistics.median(bandDepths) else { return nil }
        // tolerance = 峰附近分布跨度的一半，下限 6cm 防抖，上限 20cm 防背景混入。
        let spread = histogram.binWidth * 1.5
        let tolerance = min(max(spread, 0.06), 0.2)
        let band = max(0.02, medianDepth - tolerance)...(medianDepth + tolerance)
        return ForegroundBand(band: band, validDepthRatio: validRatio, medianDepth: medianDepth)
    }

    static func depthHistogram(_ depths: [Float], binCount: Int) -> (bins: [Int], binWidth: Float, binRanges: [ClosedRange<Float>])? {
        let valid = depths.filter { $0.isFinite && $0 > 0 }
        guard valid.count >= 10, let minValue = valid.min(), let maxValue = valid.max() else {
            return nil
        }
        guard maxValue > minValue else {
            // 全部深度相同（极端情况），直接返回单 bin。
            let center = maxValue
            return (
                bins: [valid.count],
                binWidth: 0.02,
                binRanges: [center - 0.01...center + 0.01]
            )
        }
        let binWidth = (maxValue - minValue) / Float(binCount)
        var bins = [Int](repeating: 0, count: binCount)
        var ranges: [ClosedRange<Float>] = []
        for index in 0..<binCount {
            let lower = minValue + Float(index) * binWidth
            let upper = index == binCount - 1 ? maxValue : minValue + Float(index + 1) * binWidth
            ranges.append(lower...upper)
        }
        for depth in valid {
            let index = min(binCount - 1, Int((depth - minValue) / binWidth))
            bins[index] += 1
        }
        return (bins, binWidth, ranges)
    }
}

import ARKit
import CoreGraphics
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

    /// ROI + mask 内深度直方图 → 前景深度带。
    ///
    /// 任务书第 55~61 条：
    /// - YOLO mask 存在时优先只统计 mask 内像素，背景干扰更小
    /// - percentile 2%~98% 粗裁剪，避免固定 ±6cm 把有厚度的物体后半部分删掉
    /// - valley 检测：后方出现大断层（如墙）时裁掉后景
    static func foregroundBand(
        in roi: CGRect,
        mask: CVPixelBuffer,
        from frame: ARFrame,
        stride: Int = 2
    ) -> ForegroundBand? {
        guard let data = bestDepthData(from: frame) else { return nil }
        let map = data.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return nil }
        let depthSize = CGSize(width: width, height: height)

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let confidenceMap = data.confidenceMap
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
        }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)
        let confidenceValues = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0
        guard let maskBase = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let maskStride = CVPixelBufferGetBytesPerRow(mask)
        let maskValues = maskBase.assumingMemoryBound(to: UInt8.self)

        var validCount = 0
        var totalCount = 0
        var depths: [Float] = []
        let sampleStride = max(1, stride)

        for y in 0..<height where y % sampleStride == sampleStride / 2 {
            for x in 0..<width where x % sampleStride == sampleStride / 2 {
                let displayPoint = CoordinateMapper.displayNormalized(
                    cameraPixel: x,
                    py: y,
                    cameraSize: depthSize
                )
                guard roi.contains(displayPoint) else { continue }
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
                // mask 过滤：只统计目标实例内像素。
                let maskPixel = CoordinateMapper.maskPixel(
                    normalized: displayPoint,
                    maskWidth: maskWidth,
                    maskHeight: maskHeight
                )
                guard maskValues[maskPixel.y * maskStride + maskPixel.x] > 0 else { continue }
                validCount += 1
                depths.append(depth)
            }
        }
        guard totalCount > 0 else { return nil }
        let validRatio = Float(validCount) / Float(totalCount)
        guard validCount >= 40 else { return nil }

        return buildBand(depths: depths, validRatio: validRatio)
    }

    /// 基于 mask 内深度分布构建前景带：percentile 粗裁剪 + valley 断层裁剪。
    static func buildBand(depths: [Float], validRatio: Float) -> ForegroundBand? {
        let sorted = depths.filter { $0.isFinite && $0 > 0 }.sorted()
        guard sorted.count >= 40 else { return nil }
        let lower = sorted[Int(Float(sorted.count - 1) * 0.02)]
        let upper = sorted[Int(Float(sorted.count - 1) * 0.98)]
        guard upper > lower else {
            let center = sorted[sorted.count / 2]
            let band = max(0.02, center - 0.05)...(center + 0.05)
            return ForegroundBand(band: band, validDepthRatio: validRatio, medianDepth: center)
        }

        // valley 检测：从远端向近端扫描 16 bins，找第一个显著空档；
        // 若空档之后（更远处）点数占比 < 20%，判定为背景墙等断层，裁掉。
        let binCount = 16
        let binWidth = (upper - lower) / Float(binCount)
        var bins = [Int](repeating: 0, count: binCount)
        var farCount = 0
        for depth in sorted {
            let index = min(binCount - 1, Int((depth - lower) / binWidth))
            bins[index] += 1
        }
        let peak = bins.max() ?? 1
        var cutIndex = binCount
        var behindCount = 0
        for index in stride(from: binCount - 1, through: 0, by: -1) {
            if bins[index] < max(2, peak / 7) {
                if index < cutIndex {
                    cutIndex = index
                }
            } else {
                behindCount = 0
                cutIndex = binCount
                continue
            }
            behindCount += bins[index]
            if behindCount > sorted.count / 5 {
                break
            }
        }
        let effectiveUpper = cutIndex < binCount ? lower + Float(cutIndex) * binWidth : upper
        let medianDepth = sorted[sorted.count / 2]
        let band = max(0.02, lower)...max(lower + 0.02, effectiveUpper)
        return ForegroundBand(band: band, validDepthRatio: validRatio, medianDepth: medianDepth)
    }

    /// 无 mask 版：ROI 内直接直方图（兼容旧路径，容忍 background 混入）。
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
        let depthSize = CGSize(width: width, height: height)

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
        let sampleStride = max(1, stride)

        for y in 0..<height where y % sampleStride == sampleStride / 2 {
            for x in 0..<width where x % sampleStride == sampleStride / 2 {
                // 深度像素 → 显示归一化 → ROI 判定（深度图与显示空间存在旋转）。
                let displayPoint = CoordinateMapper.displayNormalized(
                    cameraPixel: x,
                    py: y,
                    cameraSize: depthSize
                )
                guard roi.contains(displayPoint) else { continue }
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
        guard validCount >= 40 else { return nil }
        return buildBand(depths: depths, validRatio: validRatio)
    }
}

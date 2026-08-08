import ARKit
import CoreVideo
import Foundation

/// 读取 ARKit 场景深度：优先 smoothedSceneDepth，回退 sceneDepth。
enum DepthReader {
    struct Sample {
        let depth: Float
        let confidence: Float
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
}

import ARKit
import CoreVideo
import Foundation
import simd

/// 从深度图构建目标点云：只扫描 Target ROI（不扫整张深度图）。
///
/// 过滤链：ROI → mask ∩ ROI → 深度带 → 置信度 → 无效值。
/// 输出世界坐标点云，并统计深度有效率。
enum PointCloudBuilder {
    struct Configuration {
        var stride: Int = 2
        var minimumConfidence: Float = 0.5
        var depthBand: ClosedRange<Float>?
        /// 左上原点归一化 ROI。
        var roi: CGRect?
        /// 实例分割 mask（左上原点像素数据），仅采样 mask > 0 的位置。
        var mask: CVPixelBuffer?
    }

    struct Result {
        let points: [SIMD3<Float>]
        let validDepthRatio: Float
    }

    static func build(from frame: ARFrame, configuration: Configuration) -> Result {
        guard let depthData = DepthReader.bestDepthData(from: frame) else {
            return Result(points: [], validDepthRatio: 0)
        }
        let map = depthData.depthMap
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        guard width > 0, height > 0 else { return Result(points: [], validDepthRatio: 0) }

        let geometry = DepthCoordinateMapper.geometry(frame: frame, depthMap: map)

        CVPixelBufferLockBaseAddress(map, .readOnly)
        let confidenceMap = depthData.confidenceMap
        if let confidenceMap {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        }
        let mask = configuration.mask
        if let mask {
            CVPixelBufferLockBaseAddress(mask, .readOnly)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(map, .readOnly)
            if let confidenceMap {
                CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            }
            if let mask {
                CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            }
        }
        guard let base = CVPixelBufferGetBaseAddress(map) else {
            return Result(points: [], validDepthRatio: 0)
        }
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float32>.stride
        let values = base.assumingMemoryBound(to: Float32.self)

        let confidenceValues = confidenceMap
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let confidenceStride = confidenceMap.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let maskValues = mask
            .flatMap { CVPixelBufferGetBaseAddress($0) }
            .map { $0.assumingMemoryBound(to: UInt8.self) }
        let maskWidth = mask.map { CVPixelBufferGetWidth($0) } ?? 0
        let maskHeight = mask.map { CVPixelBufferGetHeight($0) } ?? 0
        let maskStride = mask.map { CVPixelBufferGetBytesPerRow($0) } ?? 0

        let stride = max(1, configuration.stride)
        let roi = configuration.roi
        var points: [SIMD3<Float>] = []
        points.reserveCapacity((width / stride) * (height / stride))
        var totalSampled = 0
        var validDepthCount = 0

        let xStart = roi.map { max(0, Int($0.minX * CGFloat(width))) } ?? 0
        let xEnd = roi.map { min(width, Int($0.maxX * CGFloat(width))) } ?? width
        let yStart = roi.map { max(0, Int($0.minY * CGFloat(height))) } ?? 0
        let yEnd = roi.map { min(height, Int($0.maxY * CGFloat(height))) } ?? height

        for y in yStart..<yEnd where y % stride == stride / 2 {
            for x in xStart..<xEnd where x % stride == stride / 2 {
                totalSampled += 1
                let depth = values[y * rowStride + x]
                let isInvalid = !depth.isFinite || depth <= 0
                let confidence: Float
                if let confidenceValues {
                    confidence = Float(confidenceValues[y * confidenceStride + x]) / 2
                } else {
                    confidence = 1
                }
                if isInvalid || confidence < configuration.minimumConfidence { continue }
                validDepthCount += 1
                if let band = configuration.depthBand, !band.contains(depth) { continue }
                if let maskValues, maskWidth > 0, maskHeight > 0 {
                    let normalized = CGPoint(x: CGFloat(x) / CGFloat(width), y: CGFloat(y) / CGFloat(height))
                    let pixel = VisionCoordinateMapper.maskPixel(
                        normalized: normalized,
                        maskWidth: maskWidth,
                        maskHeight: maskHeight
                    )
                    guard maskValues[pixel.y * maskStride + pixel.x] > 0 else { continue }
                }
                points.append(DepthCoordinateMapper.worldPoint(x: x, y: y, depth: depth, geometry: geometry))
            }
        }
        let validRatio = totalSampled > 0 ? Float(validDepthCount) / Float(totalSampled) : 0
        return Result(points: points, validDepthRatio: validRatio)
    }
}

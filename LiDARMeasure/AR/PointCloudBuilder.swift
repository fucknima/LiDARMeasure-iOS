import ARKit
import CoreVideo
import Foundation
import simd

/// 从深度图构建目标点云：只扫描 Target ROI（不扫整张深度图）。
///
/// 过滤链：显示空间 ROI → mask ∩ ROI → 深度带 → 置信度 → 无效值。
///
/// 坐标映射（任务书第 51 条）：
/// 深度像素空间（横向）与显示空间（竖屏）存在旋转关系，禁止直接把
/// depth 归一化坐标乘 mask 尺寸。每个深度像素先转换到显示归一化
/// 坐标，再查询 mask / ROI（scaleFill 下 mask 与显示空间直接对应）。
///
/// 输出世界坐标点云，并统计深度有效率。
enum PointCloudBuilder {
    struct Configuration {
        var stride: Int = 2
        var minimumConfidence: Float = 0.5
        var depthBand: ClosedRange<Float>?
        /// 显示空间归一化 ROI（左上原点）。
        var roi: CGRect?
        /// 实例分割 mask（显示空间对齐，左上原点像素数据）。
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
        let depthSize = CGSize(width: width, height: height)

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

        for y in stride / 2..<height where y % stride == stride / 2 {
            for x in stride / 2..<width where x % stride == stride / 2 {
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

                // 深度像素 → 显示归一化 → ROI / mask 判定。
                let displayPoint = CoordinateMapper.displayNormalized(
                    cameraPixel: x,
                    py: y,
                    cameraSize: depthSize
                )
                if let roi, !roi.contains(displayPoint) { continue }
                if let maskValues, maskWidth > 0, maskHeight > 0 {
                    let pixel = CoordinateMapper.maskPixel(
                        normalized: displayPoint,
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

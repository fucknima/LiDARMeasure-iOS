import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// 前景实例分割（iOS 17 系统内置）。
///
/// 关键约束：画面可能有多个前景实例，必须把与目标检测框 IoU 最大的实例
/// 单独分割出来，禁止直接使用整张前景 mask。
///
/// VNInstanceMaskObservation 不提供 boundingBox，实例框由 mask 像素扫描计算。
enum ObjectSegmenter {
    struct SegmentResult {
        let mask: CVPixelBuffer
        let instanceBox: CGRect
        let matchedIoU: Float
    }

    /// 分割与 targetBox 交叠最大的前景实例。
    ///
    /// 实例 ID 必须来自 observation.allInstances（IndexSet），
    /// 禁止把 observation 数组索引当作实例 ID。
    static func segmentInstance(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        targetBox: CGRect,
        minimumIoU: Float = 0.3
    ) throws -> SegmentResult? {
        let (observations, handler) = try runMaskRequest(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        )
        guard !observations.isEmpty else { return nil }

        var bestIoU: Float = 0
        var bestMask: CVPixelBuffer?
        for observation in observations {
            for instanceID in observation.allInstances {
                let mask = try observation.generateScaledMaskForImage(
                    forInstances: IndexSet(integer: instanceID),
                    from: handler
                )
                // mask 为左上原点像素数据，转为左下原点归一化后与检测框比 IoU。
                let maskBox = maskBoundingBox(mask)
                guard maskBox.width > 0 else { continue }
                let boxBottomLeft = VisionCoordinateMapper.bottomLeft(maskBox)
                let iou = BoxOps.intersectionOverUnion(boxBottomLeft, targetBox)
                if iou > bestIoU {
                    bestIoU = iou
                    bestMask = mask
                }
            }
        }
        guard let bestMask, bestIoU >= minimumIoU else { return nil }

        let instanceBox = VisionCoordinateMapper.bottomLeft(maskBoundingBox(bestMask))
        return SegmentResult(mask: bestMask, instanceBox: instanceBox, matchedIoU: bestIoU)
    }

    /// 全部前景实例的合并 mask（用于智能框选，作为 box 内深度聚类的辅助）。
    static func allForegroundMask(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> CVPixelBuffer? {
        let (observations, handler) = try runMaskRequest(
            pixelBuffer: pixelBuffer,
            orientation: orientation
        )
        guard let first = observations.first else { return nil }
        return try first.generateScaledMaskForImage(forInstances: first.allInstances, from: handler)
    }

    /// 从 mask 像素数据计算非零区域包围盒（左上原点归一化）。
    static func maskBoundingBox(_ mask: CVPixelBuffer) -> CGRect {
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard width > 0, height > 0 else { return .zero }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return .zero }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let values = base.assumingMemoryBound(to: UInt8.self)

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width where values[y * bytesPerRow + x] > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return .zero }
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(minY) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxY - minY + 1) / CGFloat(height)
        )
    }

    private static func runMaskRequest(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) throws -> ([VNInstanceMaskObservation], VNImageRequestHandler) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        return (request.results ?? [], handler)
    }
}

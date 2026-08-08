import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// 前景实例分割（iOS 17 系统内置）。
///
/// 关键约束：画面可能有多个前景实例，必须把与目标检测框 IoU 最大的实例
/// 单独分割出来，禁止直接使用整张前景 mask。
enum ObjectSegmenter {
    struct SegmentResult {
        let mask: CVPixelBuffer
        let instanceBox: CGRect
        let matchedIoU: Float
    }

    /// 分割与 targetBox 交叠最大的单个前景实例。
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

        var bestIndex: Int?
        var bestIoU: Float = 0
        for (index, observation) in observations.enumerated() {
            let iou = BoxOps.intersectionOverUnion(observation.boundingBox, targetBox)
            if iou > bestIoU {
                bestIoU = iou
                bestIndex = index
            }
        }
        guard let bestIndex, bestIoU >= minimumIoU else { return nil }

        let instance = observations[bestIndex]
        let mask = try instance.generateScaledMaskForImage(forInstances: [instance], from: handler)
        return SegmentResult(mask: mask, instanceBox: instance.boundingBox, matchedIoU: bestIoU)
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

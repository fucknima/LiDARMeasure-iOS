import CoreGraphics
import CoreVideo
import Foundation
import Vision

struct VisionObservation {
    let identifier: String
    let confidence: Float
    /// 归一化坐标，原点在左下角（Vision 坐标系）。
    let boundingBox: CGRect
}

/// 目标检测：优先显著性目标（无需模型，系统内置），回退分类请求。
final class ObjectDetector {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation = .right
    ) throws -> VisionObservation? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)

        let saliencyRequest = VNGenerateObjectnessBasedSaliencyImageRequest()
        try handler.perform([saliencyRequest])
        if let saliency = saliencyRequest.results?.first,
           let object = saliency.salientObjects?.first,
           object.confidence > 0.2 {
            return VisionObservation(
                identifier: "目标",
                confidence: object.confidence,
                boundingBox: object.boundingBox
            )
        }

        let classifyRequest = VNClassifyImageRequest()
        try handler.perform([classifyRequest])
        if let classification = classifyRequest.results?.first(where: { $0.confidence > 0.2 }) {
            return VisionObservation(
                identifier: classification.identifier,
                confidence: classification.confidence,
                // 分类不携带区域，整幅画面作为 fallback 区域。
                boundingBox: CGRect(x: 0, y: 0, width: 1, height: 1)
            )
        }
        return nil
    }
}

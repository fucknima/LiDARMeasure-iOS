import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// 真实目标检测：YOLOv8n CoreML（raw 输出 [1,84,8400]，App 内 decode + NMS）。
///
/// VNCoreMLRequest 负责 YUV→RGB 与 640x640 缩放（.scaleFill，归一化坐标不变），
/// 输出 raw feature 由 YOLODecoder 解码。
final class ObjectDetector {
    private let request: VNCoreMLRequest

    init?() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let url = Bundle.main.url(forResource: "ObjectDetector", withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url, configuration: configuration),
              let visionModel = try? VNCoreMLModel(for: mlModel) else {
            AppLog.vision.error("ObjectDetector model load failed")
            return nil
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        self.request = request
        AppLog.vision.info("ObjectDetector initialized (YOLOv8n raw)")
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        threshold: Float
    ) throws -> [DetectedObject] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
              let multiArray = observations.first?.featureValue.multiArrayValue else {
            return []
        }
        return YOLODecoder.decode(multiArray, threshold: threshold)
    }
}

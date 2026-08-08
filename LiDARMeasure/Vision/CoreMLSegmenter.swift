import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// YOLO26m-seg CoreML 分割模型实现（自动模式主路径）。
///
/// - VNCoreMLRequest + .scaleFill：模型输出坐标与「显示方向图像」归一化空间一致
/// - 输出两个 raw tensor（preds [1,300,38] + proto [1,32,160,160]），
///   按 shape 识别，禁止硬编码输出索引（任务书第 21 条）
/// - 解码交给 YOLO26SegDecoder
final class CoreMLSegmenter: ObjectSegmentationModel {
    private let request: VNCoreMLRequest
    private let modelName: String
    private(set) var modelInputDescription: String = ""
    private(set) var modelOutputDescription: String = ""

    init?(modelName: String = "ObjectSegmenter") {
        self.modelName = modelName
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url, configuration: configuration),
              let visionModel = try? VNCoreMLModel(for: mlModel) else {
            AppLog.vision.error("\(modelName) model load failed")
            return nil
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        self.request = request
        // 启动时记录模型规格（任务书第 22 条）。
        self.modelInputDescription = mlModel.modelDescription.inputDescriptionsByName
            .map { "\($0.key) \(shapeDescription($0.value.multiArrayConstraint?.shape))" }
            .sorted()
            .joined(separator: "; ")
        self.modelOutputDescription = mlModel.modelDescription.outputDescriptionsByName
            .map { "\($0.key) \(shapeDescription($0.value.multiArrayConstraint?.shape))" }
            .sorted()
            .joined(separator: "; ")
        AppLog.vision.info("\(modelName) loaded. inputs: \(self.modelInputDescription), outputs: \(self.modelOutputDescription)")
    }

    /// 同步执行推理（VNCoreMLRequest 实例不可并发；调用方为 actor，已保证串行）。
    func infer(pixelBuffer: CVPixelBuffer) async throws -> [SegmentedObject] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        try handler.perform([request])
        guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else {
            throw YOLO26SegDecoderError.shapeMismatch(
                description: "无 VNCoreMLFeatureValueObservation 输出"
            )
        }
        var preds: MLMultiArray?
        var proto: MLMultiArray?
        for observation in observations {
            guard let array = observation.featureValue.multiArrayValue else { continue }
            if array.shape.count == 3 {
                preds = array
            } else if array.shape.count == 4 {
                proto = array
            }
        }
        guard let preds, let proto else {
            throw YOLO26SegDecoderError.shapeMismatch(
                description: "输出缺失：preds=\(preds != nil) proto=\(proto != nil)"
            )
        }
        return try YOLO26SegDecoder.decode(
            preds: preds,
            proto: proto,
            options: .init()
        )
    }

    private func shapeDescription(_ shape: [NSNumber]?) -> String {
        shape?.map { $0.stringValue }.joined(separator: "x") ?? "?"
    }
}

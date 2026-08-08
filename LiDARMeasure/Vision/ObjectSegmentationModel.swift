import CoreVideo
import Foundation

/// 分割模型统一接口（任务书第 114 条）。
///
/// 未来可替换：YOLO26m-seg / 工业自训练模型 / 其他 CoreML 模型。
/// 禁止把 YOLO 代码散落到 ViewModel。
protocol ObjectSegmentationModel {
    func infer(pixelBuffer: CVPixelBuffer) async throws -> [SegmentedObject]
}

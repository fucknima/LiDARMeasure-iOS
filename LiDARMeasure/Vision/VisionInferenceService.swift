import ARKit
import CoreVideo
import Foundation
import Vision

/// 推理结果：区分「成功但无目标」与「推理失败」（任务书第 121 条）。
enum InferenceResult {
    case success([SegmentedObject])
    case failure(Error)
}

/// 后台推理服务：YOLO26m-seg 分割推理。
///
/// - actor 隔离，推理不阻塞主线程
/// - 节流：默认 5 FPS，根据实测 inference 耗时自适应（任务书第 31 条）
/// - 防堆积：上一帧未完成时跳过新帧（任务书第 32 条）
/// - 热降频：thermalState serious 时自动降低推理频率（任务书第 79 条）
actor VisionInferenceService {
    private let segmenter: CoreMLSegmenter?
    private var isBusy = false
    private var lastRunTime: TimeInterval = 0
    private var interval: TimeInterval = 0.2

    nonisolated let isAvailable: Bool
    nonisolated let modelName: String

    init(modelName: String = "ObjectSegmenter") {
        let segmenter = CoreMLSegmenter(modelName: modelName)
        self.segmenter = segmenter
        self.isAvailable = segmenter != nil
        self.modelName = modelName
    }

    /// 更新推理频率（热降频等场景）。
    func setInferenceRate(_ fps: Float) {
        interval = 1.0 / Double(max(1, min(10, Int(fps))))
    }

    /// 推理一帧。返回 nil 表示跳过（节流/堆积）。
    /// 推理失败返回 .failure（与「无目标」的 .success([]) 严格区分，任务书第 121 条）。
    func infer(pixelBuffer: CVPixelBuffer, threshold: Float) async -> InferenceResult? {
        guard let segmenter else {
            return .failure(AutoMeasureError.modelUnavailable)
        }
        guard !isBusy else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRunTime >= interval else { return nil }
        isBusy = true
        defer { isBusy = false }
        lastRunTime = now

        let start = Date()
        do {
            let objects = try await segmenter.infer(pixelBuffer: pixelBuffer)
            let elapsed = Date().timeIntervalSince(start) * 1000
            if !objects.isEmpty {
                AppLog.vision.info("objects=\(objects.count) inference=\(Int(elapsed))ms")
            }
            return .success(objects)
        } catch {
            AppLog.vision.error("Segmentation inference failed: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// 全部前景实例合并 mask（智能框选 fallback，任务书第 41/42 条）。
    /// 返回 nil 表示该帧跳过；无实例返回 nil。
    func allForegroundMask(pixelBuffer: CVPixelBuffer) async -> CVPixelBuffer? {
        guard !isBusy else { return nil }
        do {
            let mask = try ObjectSegmenter.allForegroundMask(
                pixelBuffer: pixelBuffer,
                orientation: .right
            )
            if mask != nil {
                AppLog.vision.info("foreground mask generated")
            }
            return mask
        } catch {
            AppLog.vision.error("Foreground mask failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

import CoreGraphics
import CoreML
import CoreVideo
import Foundation

enum YOLO26SegDecoderError: Error, LocalizedError {
    case shapeMismatch(description: String)
    case maskBufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .shapeMismatch(let description):
            return "模型输出形状不匹配：\(description)"
        case .maskBufferCreationFailed:
            return "mask 缓冲创建失败"
        }
    }
}

/// YOLO26m-seg 输出解码。
///
/// 模型输出（PyTorch 与 CoreML 一致，需先经 Scripts/test_coreml_output.py 验证）：
/// - preds  [1, 300, 38]：NMS 后 top-300 检测
///   - ch0-3: xyxy（640x640 输入空间像素值）
///   - ch4: confidence
///   - ch5: class index
///   - ch6-37: 32 个 mask coefficients
/// - proto  [1, 32, 160, 160]：mask prototypes
///
/// 模型已内置 NMS；Swift 端仍做一次 class-aware NMS 防御性去重
/// （不同类别之间绝不互相抑制）。
enum YOLO26SegDecoder {
    struct DecodeOptions {
        var confidenceThreshold: Float = 0.30
        var iouThreshold: Float = 0.45
        var maskThreshold: Float = 0.50
    }

    static let maxDetections = 300
    static let maskPrototypeCount = 32
    static let maskSize = 160
    static let inputSize: Float = 640

    struct DecodedBox {
        let classIndex: Int
        let confidence: Float
        let box: CGRect
        let coefficients: [Float]

        init(classIndex: Int, confidence: Float, box: CGRect, coefficients: [Float] = []) {
            self.classIndex = classIndex
            self.confidence = confidence
            self.box = box
            self.coefficients = coefficients
        }
    }

    static func decode(
        preds: MLMultiArray,
        proto: MLMultiArray,
        options: DecodeOptions
    ) throws -> [SegmentedObject] {
        // 形状校验：不匹配直接报错，禁止静默返回 []（任务书 120/126/127）。
        guard preds.shape.count == 3,
              Int(truncating: preds.shape[1]) == maxDetections else {
            throw YOLO26SegDecoderError.shapeMismatch(
                description: "preds shape=\(MLMultiArrayAccessor.shapeDescription(of: preds))，期望 [1, 300, 38]"
            )
        }
        let channels = Int(truncating: preds.shape[2])
        guard channels >= 6 + maskPrototypeCount else {
            throw YOLO26SegDecoderError.shapeMismatch(
                description: "preds 通道数 \(channels) 不足 38"
            )
        }
        guard proto.shape.count == 4,
              Int(truncating: proto.shape[1]) == maskPrototypeCount,
              Int(truncating: proto.shape[2]) == maskSize,
              Int(truncating: proto.shape[3]) == maskSize else {
            throw YOLO26SegDecoderError.shapeMismatch(
                description: "proto shape=\(MLMultiArrayAccessor.shapeDescription(of: proto))，期望 [1, 32, 160, 160]"
            )
        }

        var candidates: [DecodedBox] = []
        candidates.reserveCapacity(32)
        for detection in 0..<maxDetections {
            guard let confidence = MLMultiArrayAccessor.value(preds, indices: [0, detection, 4]),
                  confidence >= options.confidenceThreshold else { continue }
            let classIndex = Int(MLMultiArrayAccessor.value(preds, indices: [0, detection, 5]) ?? -1)
            guard classIndex >= 0, classIndex < COCOClassNames.names.count else { continue }

            let x1 = (MLMultiArrayAccessor.value(preds, indices: [0, detection, 0]) ?? 0) / inputSize
            let y1 = (MLMultiArrayAccessor.value(preds, indices: [0, detection, 1]) ?? 0) / inputSize
            let x2 = (MLMultiArrayAccessor.value(preds, indices: [0, detection, 2]) ?? 0) / inputSize
            let y2 = (MLMultiArrayAccessor.value(preds, indices: [0, detection, 3]) ?? 0) / inputSize
            guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite,
                  x2 > x1, y2 > y1 else { continue }

            var coefficients: [Float] = []
            coefficients.reserveCapacity(maskPrototypeCount)
            for channel in 0..<maskPrototypeCount {
                let value = MLMultiArrayAccessor.value(preds, indices: [0, detection, 6 + channel]) ?? 0
                coefficients.append(value)
            }

            candidates.append(DecodedBox(
                classIndex: classIndex,
                confidence: confidence,
                box: CGRect(x: CGFloat(x1), y: CGFloat(y1), width: CGFloat(x2 - x1), height: CGFloat(y2 - y1)),
                coefficients: coefficients
            ))
        }

        // class-aware NMS 防御性去重。
        let kept = classAwareNMS(candidates, iouThreshold: options.iouThreshold)

        var result: [SegmentedObject] = []
        result.reserveCapacity(kept.count)
        for box in kept {
            guard let mask = try? decodeMask(
                coefficients: box.coefficients,
                proto: proto,
                threshold: options.maskThreshold
            ) else {
                AppLog.vision.error("Mask decode failed for detection")
                continue
            }
            result.append(SegmentedObject(
                frameID: UUID(),
                stableID: UUID(),
                label: COCOClassNames.names[box.classIndex],
                confidence: box.confidence,
                classIndex: box.classIndex,
                boundingBox: box.box,
                mask: mask,
                maskCoverage: maskCoverage(mask)
            ))
        }
        return result
    }

    /// 标准 class-aware NMS：只抑制同类且 IoU 超阈值的候选。
    static func classAwareNMS(_ candidates: [DecodedBox], iouThreshold: Float) -> [DecodedBox] {
        var remaining = candidates.sorted { $0.confidence > $1.confidence }
        var kept: [DecodedBox] = []
        while let best = remaining.first {
            kept.append(best)
            remaining.removeFirst()
            remaining = remaining.filter { candidate in
                guard candidate.classIndex == best.classIndex else { return true }
                return BoxOps.intersectionOverUnion(candidate.box, best.box) <= iouThreshold
            }
        }
        return kept
    }

    /// mask = sigmoid(proto ⊗ coefficients) > threshold，输出 160x160 OneComponent8 buffer。
    static func decodeMask(
        coefficients: [Float],
        proto: MLMultiArray,
        threshold: Float
    ) throws -> CVPixelBuffer {
        let width = maskSize
        let height = maskSize
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: false,
            kCVPixelBufferCGBitmapContextCompatibilityKey: false
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw YOLO26SegDecoderError.maskBufferCreationFailed
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw YOLO26SegDecoderError.maskBufferCreationFailed
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let values = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for channel in 0..<maskPrototypeCount {
                    let protoValue = MLMultiArrayAccessor.value(
                        proto,
                        indices: [0, channel, y, x]
                    ) ?? 0
                    sum += protoValue * coefficients[channel]
                }
                let sigmoid = 1 / (1 + exp(-sum))
                values[y * bytesPerRow + x] = sigmoid > threshold ? 255 : 0
            }
        }
        return pixelBuffer
    }

    static func maskCoverage(_ mask: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        guard width > 0, height > 0 else { return 0 }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let values = base.assumingMemoryBound(to: UInt8.self)
        var count = 0
        for y in 0..<height {
            for x in 0..<width where values[y * bytesPerRow + x] > 0 {
                count += 1
            }
        }
        return Float(count) / Float(width * height)
    }
}

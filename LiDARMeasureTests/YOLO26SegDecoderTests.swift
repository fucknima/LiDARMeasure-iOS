import CoreML
import CoreVideo
import XCTest
@testable import LiDARMeasure

final class YOLO26SegDecoderTests: XCTestCase {
    private func makePreds() throws -> MLMultiArray {
        try MLMultiArray(shape: [1, 300, 38], dataType: .float32)
    }

    private func makeProto() throws -> MLMultiArray {
        try MLMultiArray(shape: [1, 32, 160, 160], dataType: .float32)
    }

    private func fillProtoConstant(_ proto: MLMultiArray, channel: Int, value: Float) {
        for y in 0..<160 {
            for x in 0..<160 {
                proto[0, channel, y, x] = NSNumber(value: value)
            }
        }
    }

    func testDecodeSingleDetection() throws {
        let preds = try makePreds()
        preds[0, 0, 0] = 100   // x1
        preds[0, 0, 1] = 120   // y1
        preds[0, 0, 2] = 240   // x2
        preds[0, 0, 3] = 280   // y2
        preds[0, 0, 4] = 0.9   // confidence
        preds[0, 0, 5] = 0     // class 0 = person
        let proto = try makeProto()

        let objects = try YOLO26SegDecoder.decode(preds: preds, proto: proto, options: .init())
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(objects[0].label, "person")
        XCTAssertEqual(objects[0].confidence, 0.9, accuracy: 0.0001)
        XCTAssertEqual(objects[0].boundingBox.minX, 100.0 / 640.0, accuracy: 0.0001)
        XCTAssertEqual(objects[0].boundingBox.maxY, 280.0 / 640.0, accuracy: 0.0001)
    }

    func testLowConfidenceFiltered() throws {
        let preds = try makePreds()
        preds[0, 0, 0] = 100
        preds[0, 0, 1] = 100
        preds[0, 0, 2] = 200
        preds[0, 0, 3] = 200
        preds[0, 0, 4] = 0.1   // 低于默认阈值 0.3
        preds[0, 0, 5] = 0
        let proto = try makeProto()
        let objects = try YOLO26SegDecoder.decode(preds: preds, proto: proto, options: .init())
        XCTAssertTrue(objects.isEmpty)
    }

    func testClassAwareNMSKeepsDifferentClasses() throws {
        // 两个框高度重叠但类别不同 → 都必须保留（任务书第 24 条）。
        let a = YOLO26SegDecoder.DecodedBox(classIndex: 56, confidence: 0.9, box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))
        let b = YOLO26SegDecoder.DecodedBox(classIndex: 0, confidence: 0.8, box: CGRect(x: 0.21, y: 0.21, width: 0.5, height: 0.5))
        let kept = YOLO26SegDecoder.classAwareNMS([a, b], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 2, "不同类别的重叠框不应互相抑制")
    }

    func testClassAwareNMSKeepsHighestConfidenceWithinClass() throws {
        let high = YOLO26SegDecoder.DecodedBox(classIndex: 56, confidence: 0.95, box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))
        let low = YOLO26SegDecoder.DecodedBox(classIndex: 56, confidence: 0.8, box: CGRect(x: 0.21, y: 0.21, width: 0.5, height: 0.5))
        let kept = YOLO26SegDecoder.classAwareNMS([high, low], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].confidence, 0.95, accuracy: 0.0001)
    }

    func testClassAwareNMSKeepsSeparateBoxes() throws {
        let a = YOLO26SegDecoder.DecodedBox(classIndex: 56, confidence: 0.9, box: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        let b = YOLO26SegDecoder.DecodedBox(classIndex: 56, confidence: 0.8, box: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2))
        let kept = YOLO26SegDecoder.classAwareNMS([a, b], iouThreshold: 0.45)
        XCTAssertEqual(kept.count, 2)
    }

    func testMaskDecodeConstantPrototype() throws {
        // proto 全 1 + coeff 5 → sigmoid(5) ≈ 0.993 > 0.5 → mask 全 255。
        let proto = try makeProto()
        fillProtoConstant(proto, channel: 0, value: 1)
        var coefficients = [Float](repeating: 0, count: 32)
        coefficients[0] = 5
        let mask = try YOLO26SegDecoder.decodeMask(coefficients: coefficients, proto: proto, threshold: 0.5)
        XCTAssertEqual(CVPixelBufferGetWidth(mask), 160)
        XCTAssertEqual(CVPixelBufferGetHeight(mask), 160)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(mask)!
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let values = base.assumingMemoryBound(to: UInt8.self)
        XCTAssertEqual(values[80 * bytesPerRow + 80], 255)
        XCTAssertEqual(YOLO26SegDecoder.maskCoverage(mask), 1.0, accuracy: 0.001)
    }

    func testMaskDecodeZeroPrototypeIsEmpty() throws {
        // proto 全 0 + coeff 0 → sigmoid(0) = 0.5，不 > 0.5 → 全 0。
        let proto = try makeProto()
        let coefficients = [Float](repeating: 0, count: 32)
        let mask = try YOLO26SegDecoder.decodeMask(coefficients: coefficients, proto: proto, threshold: 0.5)
        XCTAssertEqual(YOLO26SegDecoder.maskCoverage(mask), 0, accuracy: 0.001)
    }

    func testShapeMismatchThrows() {
        let proto = try! makeProto()
        let badPreds = try! MLMultiArray(shape: [1, 100, 38], dataType: .float32)
        XCTAssertThrowsError(try YOLO26SegDecoder.decode(preds: badPreds, proto: proto, options: .init())) { error in
            guard case YOLO26SegDecoderError.shapeMismatch = error else {
                return XCTFail("expected shapeMismatch, got \(error)")
            }
        }
    }
}

import CoreVideo
import UIKit
import XCTest
@testable import LiDARMeasure

final class DetectorTests: XCTestCase {
    private func makeObject(
        label: String,
        confidence: Float,
        box: CGRect,
        stableID: UUID = UUID()
    ) -> SegmentedObject {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            160, 160,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )
        return SegmentedObject(
            frameID: UUID(),
            stableID: stableID,
            label: label,
            confidence: confidence,
            classIndex: 0,
            boundingBox: box,
            mask: pixelBuffer!,
            maskCoverage: 0.5
        )
    }

    func testIntersectionOverUnion() {
        let a = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let b = CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5)
        XCTAssertEqual(BoxOps.intersectionOverUnion(a, b), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testIoUZeroForDisjointBoxes() {
        let a = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)
        XCTAssertEqual(BoxOps.intersectionOverUnion(a, b), 0, accuracy: 0.0001)
    }

    func testTrackerKeepsStableIDAcrossFrames() {
        var tracker = ObjectTracker()
        let first = makeObject(label: "chair", confidence: 0.8, box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4))
        let tracks1 = tracker.update(detections: [first])
        XCTAssertEqual(tracks1.count, 1)
        let stableID = tracks1[0].stableID

        // 轻微位移 → 同一 track，stableID 不变。
        let second = makeObject(label: "chair", confidence: 0.8, box: CGRect(x: 0.22, y: 0.21, width: 0.3, height: 0.4))
        let tracks2 = tracker.update(detections: [second])
        XCTAssertEqual(tracks2.count, 1)
        XCTAssertEqual(tracks2[0].stableID, stableID)
    }

    func testTrackerKeepsTrackDuringShortMiss() {
        var tracker = ObjectTracker()
        let first = makeObject(label: "chair", confidence: 0.8, box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4))
        let tracks1 = tracker.update(detections: [first])
        let stableID = tracks1[0].stableID

        // 目标短暂消失（<=3 帧）→ track 保留。
        for _ in 0..<3 {
            let tracks = tracker.update(detections: [])
            XCTAssertEqual(tracks.count, 1)
            XCTAssertEqual(tracks[0].stableID, stableID)
        }
        // 超过 maxMissed(3) → 删除。
        let tracks = tracker.update(detections: [])
        XCTAssertTrue(tracks.isEmpty)
    }

    func testTrackerNewObjectGetsNewStableID() {
        var tracker = ObjectTracker()
        let first = makeObject(label: "chair", confidence: 0.8, box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4))
        let tracks1 = tracker.update(detections: [first])
        let other = makeObject(label: "bottle", confidence: 0.8, box: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.3))
        let tracks2 = tracker.update(detections: [other])
        XCTAssertEqual(tracks2.count, 2)
        XCTAssertNotEqual(tracks2[1].stableID, tracks1[0].stableID)
    }

    func testCOCOTranslation() {
        XCTAssertEqual(COCOLabelTranslator.translate("chair"), "椅子")
        XCTAssertEqual(COCOLabelTranslator.translate("bottle"), "瓶子")
        XCTAssertEqual(COCOLabelTranslator.translate("unknown_thing"), "unknown_thing")
    }

    func testCameraOrientationMapping() {
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.portrait), .right)
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.landscapeLeft), .up)
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.portraitUpsideDown), .left)
    }
}

import UIKit
import XCTest
@testable import LiDARMeasure

final class DetectorTests: XCTestCase {
    func testIntersectionOverUnion() {
        let a = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let b = CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5)
        // 交集 0.125，并集 0.375 → IoU = 1/3。
        XCTAssertEqual(BoxOps.intersectionOverUnion(a, b), 1.0 / 3.0, accuracy: 0.0001)
    }

    func testIoUZeroForDisjointBoxes() {
        let a = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let b = CGRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2)
        XCTAssertEqual(BoxOps.intersectionOverUnion(a, b), 0, accuracy: 0.0001)
    }

    func testTrackerKeepsIDAcrossFrames() {
        var tracker = ObjectTracker()
        let first = DetectedObject(
            id: UUID(),
            label: "chair",
            confidence: 0.8,
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        )
        let tracked = tracker.track([first])
        XCTAssertEqual(tracked?.id, first.id)

        let second = DetectedObject(
            id: UUID(),
            label: "chair",
            confidence: 0.8,
            boundingBox: CGRect(x: 0.22, y: 0.21, width: 0.3, height: 0.4)
        )
        let next = tracker.track([second])
        XCTAssertEqual(next?.id, first.id, "tracker should keep the stable ID")
    }

    func testTrackerClearsWhenTargetGone() {
        var tracker = ObjectTracker()
        let first = DetectedObject(
            id: UUID(),
            label: "chair",
            confidence: 0.8,
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        )
        _ = tracker.track([first])
        XCTAssertNil(tracker.track([]))
    }

    func testCOCOTranslation() {
        XCTAssertEqual(COCOLabelTranslator.translate("chair"), "椅子")
        XCTAssertEqual(COCOLabelTranslator.translate("bottle"), "瓶子")
        XCTAssertEqual(COCOLabelTranslator.translate("laptop"), "笔记本电脑")
        XCTAssertEqual(COCOLabelTranslator.translate("unknown_thing"), "unknown_thing")
    }

    func testCameraOrientationMapping() {
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.portrait), .right)
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.landscapeLeft), .up)
        XCTAssertEqual(CameraOrientationMapper.orientation(for: UIInterfaceOrientation.portraitUpsideDown), .left)
    }
}

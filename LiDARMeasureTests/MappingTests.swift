import XCTest
@testable import LiDARMeasure

final class MappingTests: XCTestCase {
    func testVisionBoxToTopLeftConversion() {
        // Vision 左下原点 box → 左上原点。
        let box = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let topLeft = VisionCoordinateMapper.topLeft(box)
        XCTAssertEqual(topLeft.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(topLeft.minY, 0.2, accuracy: 0.0001)
        XCTAssertEqual(topLeft.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(topLeft.height, 0.5, accuracy: 0.0001)
    }

    func testTopLeftToVisionBoxRoundTrip() {
        let box = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5)
        let roundTrip = VisionCoordinateMapper.bottomLeft(VisionCoordinateMapper.topLeft(box))
        XCTAssertEqual(roundTrip.minX, box.minX, accuracy: 0.0001)
        XCTAssertEqual(roundTrip.minY, box.minY, accuracy: 0.0001)
    }

    func testViewBoxMapping() {
        let normalized = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        let viewBox = VisionCoordinateMapper.viewBox(from: normalized, in: CGSize(width: 400, height: 800))
        XCTAssertEqual(viewBox.minX, 100, accuracy: 0.0001)
        XCTAssertEqual(viewBox.minY, 400, accuracy: 0.0001)
        XCTAssertEqual(viewBox.width, 200, accuracy: 0.0001)
        XCTAssertEqual(viewBox.height, 200, accuracy: 0.0001)
    }

    func testMaskPixelMapping() {
        let pixel = VisionCoordinateMapper.maskPixel(
            normalized: CGPoint(x: 0.5, y: 0.5),
            maskWidth: 640,
            maskHeight: 640
        )
        XCTAssertEqual(pixel.x, 320)
        XCTAssertEqual(pixel.y, 320)
    }
}

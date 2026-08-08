import XCTest
@testable import LiDARMeasure

final class UnitConversionTests: XCTestCase {
    func testCentimeterConversion() {
        XCTAssertEqual(MeasurementUnit.centimeter.value(fromMeters: 0.425), 42.5, accuracy: 0.0001)
    }

    func testMillimeterAndInchConversion() {
        XCTAssertEqual(MeasurementUnit.millimeter.value(fromMeters: 1), 1000, accuracy: 0.0001)
        XCTAssertEqual(MeasurementUnit.inch.value(fromMeters: 0.0254), 1, accuracy: 0.0001)
    }

    func testMeterPassThrough() {
        XCTAssertEqual(MeasurementUnit.meter.value(fromMeters: 3.2), 3.2, accuracy: 0.0001)
    }

    func testFormatting() {
        XCTAssertEqual(MeasurementUnit.centimeter.format(0.425), "42.5 cm")
        XCTAssertEqual(MeasurementUnit.meter.format(1.0), "1.0 m")
    }
}

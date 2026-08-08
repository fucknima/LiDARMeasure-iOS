import XCTest
@testable import LiDARMeasure

final class MeasurementTests: XCTestCase {
    func testSmootherUsesMedian() {
        var smoother = MeasurementSmoother(windowSize: 5, relativeTolerance: 0.02, stableFrameCount: 3)
        for _ in 0..<5 {
            _ = smoother.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        XCTAssertEqual(smoother.current?.width ?? 0, 0.425, accuracy: 0.0001)
        XCTAssertEqual(smoother.current?.height ?? 0, 0.312, accuracy: 0.0001)
    }

    func testSmootherLocksAfterStableSamples() {
        var smoother = MeasurementSmoother(windowSize: 5, relativeTolerance: 0.02, stableFrameCount: 3)
        XCTAssertFalse(smoother.isStable)
        for _ in 0..<3 {
            _ = smoother.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        XCTAssertTrue(smoother.isStable)
    }

    func testSmootherResetClearsState() {
        var smoother = MeasurementSmoother(windowSize: 5, relativeTolerance: 0.02, stableFrameCount: 3)
        for _ in 0..<3 {
            _ = smoother.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        smoother.reset()
        XCTAssertFalse(smoother.isStable)
        XCTAssertNil(smoother.current)
    }

    func testQualityGradesPoorWithBadConditions() {
        let quality = MeasurementQualityEvaluator.evaluate(
            trackingLimited: true,
            depthConfidence: 0.2,
            pointCount: 4,
            distanceMeters: 5,
            stability: 0
        )
        XCTAssertEqual(quality.grade, .poor)
    }

    func testQualityGradesExcellentWithGoodConditions() {
        let quality = MeasurementQualityEvaluator.evaluate(
            trackingLimited: false,
            depthConfidence: 1,
            pointCount: 2000,
            distanceMeters: 1,
            stability: 1
        )
        XCTAssertEqual(quality.grade, .excellent)
    }

    func testRecordPrimaryTextForLength() {
        let record = MeasurementRecord(
            date: Date(),
            mode: .manualLength,
            dimensions: MeasurementDimensions(width: 0.3, height: 0, depth: 0),
            unit: .centimeter,
            distanceMeters: 0.3
        )
        XCTAssertEqual(record.primaryText, "长度 30.0 cm")
    }
}

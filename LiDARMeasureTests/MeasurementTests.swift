import XCTest
@testable import LiDARMeasure

final class MeasurementTests: XCTestCase {
    func testStabilizerUsesMedian() {
        var stabilizer = DimensionStabilizer(windowSize: 5, stableThreshold: 0.03, lockFrameCount: 3)
        for _ in 0..<5 {
            _ = stabilizer.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        XCTAssertEqual(stabilizer.current?.width ?? 0, 0.425, accuracy: 0.0001)
        XCTAssertEqual(stabilizer.current?.height ?? 0, 0.312, accuracy: 0.0001)
        XCTAssertEqual(stabilizer.current?.depth ?? 0, 0.281, accuracy: 0.0001)
    }

    func testStabilizerLocksAfterStableSamples() {
        var stabilizer = DimensionStabilizer(windowSize: 12, stableThreshold: 0.03, lockFrameCount: 5)
        XCTAssertFalse(stabilizer.isLocked)
        for _ in 0..<5 {
            _ = stabilizer.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        XCTAssertTrue(stabilizer.isLocked)
    }

    func testStabilizerDoesNotLockWithJitter() {
        var stabilizer = DimensionStabilizer(windowSize: 12, stableThreshold: 0.03, lockFrameCount: 5)
        for index in 0..<10 {
            _ = stabilizer.add(MeasurementDimensions(
                width: 0.425 + (index.isMultiple(of: 2) ? 0.05 : 0),
                height: 0.312,
                depth: 0.281
            ))
        }
        XCTAssertFalse(stabilizer.isLocked)
    }

    func testStabilizerResetClearsState() {
        var stabilizer = DimensionStabilizer(windowSize: 12, stableThreshold: 0.03, lockFrameCount: 5)
        for _ in 0..<5 {
            _ = stabilizer.add(MeasurementDimensions(width: 0.425, height: 0.312, depth: 0.281))
        }
        stabilizer.reset()
        XCTAssertFalse(stabilizer.isLocked)
        XCTAssertNil(stabilizer.current)
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

    func testAutoMeasureErrorMessages() {
        XCTAssertEqual(AutoMeasureError.noObject.message, "未检测到支持的目标，可点击框选")
        XCTAssertEqual(AutoMeasureError.insufficientPoints.message, "物体区域有效深度点过少")
    }
}

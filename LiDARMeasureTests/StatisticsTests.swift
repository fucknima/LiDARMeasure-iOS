import XCTest
@testable import LiDARMeasure

final class StatisticsTests: XCTestCase {
    func testMedianWithOddCount() {
        XCTAssertEqual(RobustStatistics.median([1, 2, 3]) ?? 0, 2, accuracy: 0.0001)
    }

    func testMedianWithEvenCount() {
        XCTAssertEqual(RobustStatistics.median([1, 2, 3, 100]) ?? 0, 2.5, accuracy: 0.0001)
    }

    func testMedianIgnoresNonFinite() {
        let values: [Float] = [1, 2, 3, .infinity, .nan]
        XCTAssertEqual(RobustStatistics.median(values) ?? 0, 2, accuracy: 0.0001)
    }

    func testMAD() {
        let values: [Float] = [1, 2, 3, 100]
        XCTAssertEqual(RobustStatistics.mad(values) ?? 0, 1, accuracy: 0.0001)
    }

    func testMADFilterRemovesExtremeOutlier() {
        let values: [Float] = [1, 2, 3, 4, 5, 100]
        let filtered = RobustStatistics.filterByMAD(values)
        XCTAssertFalse(filtered.contains(100))
        XCTAssertEqual(filtered.count, 5)
    }

    func testIQRFilterRemovesExtremeOutlier() {
        let values: [Float] = [1, 2, 3, 4, 5, 100]
        let filtered = RobustStatistics.filterByIQR(values)
        XCTAssertFalse(filtered.contains(100))
        XCTAssertEqual(filtered.count, 5)
    }
}

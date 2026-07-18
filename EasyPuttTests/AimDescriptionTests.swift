import XCTest
@testable import EasyPutt

final class AimDescriptionTests: XCTestCase {

    func testCenterWhenWithinTwoCentimeters() {
        XCTAssertEqual(describeAimOffset(centimeters: 0), "홀컵 중앙")
        XCTAssertEqual(describeAimOffset(centimeters: 1.9), "홀컵 중앙")
        XCTAssertEqual(describeAimOffset(centimeters: -1.9), "홀컵 중앙")
    }

    func testInsideEdgeBetweenTwoAndCupRadius() {
        XCTAssertEqual(describeAimOffset(centimeters: 3.0), "오른쪽 홀컵 안쪽")
        XCTAssertEqual(describeAimOffset(centimeters: -3.0), "왼쪽 홀컵 안쪽")
    }

    func testOneBallOutBetweenCupRadiusAndCupRadiusPlusBall() {
        // cupRadius(5.4cm)부터 시작 — 이분 상한이 배타적이라 정확히 5.4는 다음 구간에 속한다
        XCTAssertEqual(describeAimOffset(centimeters: 5.4), "오른쪽 홀컵 밖 (공 1개)")
        XCTAssertEqual(describeAimOffset(centimeters: 8.0), "오른쪽 홀컵 밖 (공 1개)")
        XCTAssertEqual(describeAimOffset(centimeters: -8.0), "왼쪽 홀컵 밖 (공 1개)")
    }

    func testCupsOutBeyondOneBallDistance() {
        // aimInMeters=0.2 → cups = (0.2 - 0.054) / 0.108 = 1.35185..
        // roundedCups = round(1.35185 * 2) / 2 = round(2.7037) / 2 = 3 / 2 = 1.5
        XCTAssertEqual(describeAimOffset(centimeters: 20.0), "오른쪽 1.5컵 아웃")
        XCTAssertEqual(describeAimOffset(centimeters: -20.0), "왼쪽 1.5컵 아웃")
    }
}

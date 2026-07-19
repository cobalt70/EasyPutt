//
//  PuttRangeFinderVerifyTests.swift
//  EasyPuttTests
//
//  Created by Gi Woo Kim on 7/16/26.
//  Updated by Gi Woo Kim on 7/19/26.
//

import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderVerifyTests: XCTestCase {

    private func makeGentleSlopeTerrain() -> TerrainSampleStore {
        let store = TerrainSampleStore()
        let normal = simd_normalize(simd_float3(0.03, 1, 0))
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: normal)
                z += 0.2
            }
            x += 0.2
        }
        return store
    }

    func testVerifyCorrectsADeliberatelyWrongCandidate() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        // 의도적으로 부정확한 후보: 방향이 옆으로 치우쳐 있고 속도도 다름.
        let wrongCandidate = PuttSolution(direction: simd_normalize(simd_float3(1.0, 0, 0.3)), speed: 0.5)

        let verified = finder.verify(wrongCandidate, ballPosition: ball, holePosition: hole)

        XCTAssertNotNil(verified, "보정 반복이 수렴해서 유효한 candidate를 반환해야 한다")
    }

    func testVerifyReturnsNilWhenTerrainRunsOut() {
        // 지형 샘플이 전혀 없는 상황: TerrainSampleStore.nearestNormal(to:)는 저장소가
        // 비어있을 때만 nil을 반환한다(거리 기준 컷오프가 없어, 샘플이 하나라도 있으면
        // 질의 지점이 아무리 멀어도 가장 가까운 샘플의 법선을 그대로 돌려준다). 따라서
        // "지형 데이터가 없어서 시뮬레이션을 진행할 수 없는" 상황은 빈 저장소로 재현한다.
        let store = TerrainSampleStore()
        let finder = PuttRangeFinder(terrain: store)

        let candidate = PuttSolution(direction: simd_float3(1, 0, 0), speed: 1.0)
        let verified = finder.verify(candidate, ballPosition: simd_float3(-1.0, 0, 0), holePosition: simd_float3(100, 0, 0))

        XCTAssertNil(verified)
    }

    func testVerifySuccessfulCandidateIncludesPathThatReachesTheHole() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let wrongCandidate = PuttSolution(direction: simd_normalize(simd_float3(1.0, 0, 0.3)), speed: 0.5)
        let verified = finder.verify(wrongCandidate, ballPosition: ball, holePosition: hole)

        XCTAssertNotNil(verified)
        guard let verified = verified else { return }
        XCTAssertFalse(verified.path.isEmpty, "성공한 candidate는 시뮬레이션 경로를 담고 있어야 한다")

        guard let firstPoint = verified.path.first else {
            XCTFail("path가 비어있으면 안 된다")
            return
        }
        XCTAssertEqual(firstPoint.x, ball.x, accuracy: 0.01, "경로의 첫 점은 공의 실제 위치여야 한다")
        XCTAssertEqual(firstPoint.z, ball.z, accuracy: 0.01)

        // path는 5스텝마다 다운샘플링되므로, 기록된 점들 사이에서 공이 홀컵을
        // "건너뛰어" 지나갈 수 있다(홀인 판정 자체는 verify() 내부에서 전체 해상도
        // 궤적으로 이미 수행됨). 여기서는 시각화 용도로 경로가 홀컵 근처까지
        // 도달하는지만 확인한다 — 허용치는 캡처 반경 + 샘플 간 최대 이동거리 여유.
        let closestApproach = verified.path.map { point in
            simd_distance(simd_float3(point.x, 0, point.z), simd_float3(hole.x, 0, hole.z))
        }.min() ?? .greatestFiniteMagnitude
        XCTAssertLessThanOrEqual(
            closestApproach,
            0.1,
            "경로 어딘가는 홀컵 근처(10cm 이내)까지 접근해야 한다"
        )
    }

    func testBackwardOnlyCandidateHasEmptyPath() {
        // verify()를 거치지 않은 순수 PuttSolution(direction:speed:)은 path가 비어있어야
        // 한다 — 기존 호출부(backwardCandidate, correct())가 컴파일과 동작 모두
        // 그대로 유지되는지 확인한다.
        let candidate = PuttSolution(direction: simd_float3(1, 0, 0), speed: 0.5)
        XCTAssertTrue(candidate.path.isEmpty)
    }
}

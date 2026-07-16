import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderBackwardTests: XCTestCase {

    /// 완만한 등경사 지형(홀컵 방향으로 내리막)을 만든다 — x가 커질수록 낮아짐.
    private func makeGentleSlopeTerrain() -> TerrainSampleStore {
        let store = TerrainSampleStore()
        let normal = simd_normalize(simd_float3(0.03, 1, 0)) // ~1.7도, 내리막은 +x 방향
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

    func testBackwardCandidateFindsPlausibleDirectionAndSpeed() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        // 공에서 홀컵으로 가려면 +x 방향으로 쳐야 한다 (내리막과 일치).
        XCTAssertGreaterThan(candidate.direction.x, 0.9)
        // 완만한 내리막에서 2.5m 거리를 커버하려면 어느 정도 속도가 필요하다 (느슨한 범위).
        XCTAssertGreaterThan(candidate.speed, 0.1)
        XCTAssertLessThan(candidate.speed, 5.0)
    }

    func testBackwardCandidateReturnsNilWithoutTerrainData() {
        let emptyTerrain = TerrainSampleStore()
        let finder = PuttRangeFinder(terrain: emptyTerrain)
        let candidate = finder.backwardCandidate(
            holePosition: simd_float3(1.5, 0, 0),
            ballPosition: simd_float3(-1.0, 0, 0),
            holeCrossingSpeed: 0.08
        )
        XCTAssertNil(candidate)
    }

    func testBackwardCandidateReturnsNilForZeroOrNegativeCrossingSpeed() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let candidate = finder.backwardCandidate(
            holePosition: simd_float3(1.5, 0, 0),
            ballPosition: simd_float3(-1.0, 0, 0),
            holeCrossingSpeed: 0
        )
        XCTAssertNil(candidate)
    }

    func testBackwardCandidateOnFlatGroundFallsBackToStraightLine() {
        let store = TerrainSampleStore()
        let flatNormal = simd_float3(0, 1, 0)
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: flatNormal)
                z += 0.2
            }
            x += 0.2
        }
        let finder = PuttRangeFinder(terrain: store)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        // 평지에는 자연스러운 낙하 방향이 없으므로, 공→홀컵 직선 방향을 폴백으로 쓴다.
        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        XCTAssertEqual(candidate.direction.x, 1.0, accuracy: 0.01)
        XCTAssertEqual(candidate.direction.z, 0.0, accuracy: 0.01)
    }

    func testBackwardCandidateOnUphillPuttFallsBackToStraightLine() {
        // makeGentleSlopeTerrain()의 내리막은 항상 +x 방향이다. 홀컵을 공보다
        // -x쪽(더 높은 쪽)에 두면, 홀컵에서의 최대 경사(+x)는 공 반대쪽을 향하게 된다 —
        // 오르막 퍼팅. 이 경우 최대 경사 대신 공→홀컵 직선을 써야 한다.
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(-1.5, 0, 0)
        let ball = simd_float3(1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        // 공에서 홀컵으로 가려면 -x 방향(오르막)으로 쳐야 한다.
        XCTAssertLessThan(candidate.direction.x, -0.9)
    }
}

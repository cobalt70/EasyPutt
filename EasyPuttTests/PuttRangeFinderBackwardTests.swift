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

    func testBackwardCandidateReturnsNilWhenCrossingSpeedBelowPhysicalMinimumOnSteepSlope() {
        // 6% 경사(내리막은 +x 방향) — 실제 그린의 90% 이상이 3% 미만이고 5%를 넘는 경우는
        // 거의 없지만, 이 값은 그 드문 상한 근처를 대표한다. accelMag(~0.42)가
        // rollingResistance(0.35 기본값)를 넘어서므로 이 경사는 순내리막 가속 상태다.
        // 이 정도 경사+거리(2.5m)에서 물리적으로 가능한 최소 통과속도는 대략
        // v_hole_min = sqrt(2*(accelMag-rollingResistance)*distance) ≈ sqrt(2*0.069*2.5)
        // ≈ 0.59 m/s이므로, 실제 다잉 퍼팅 통과속도 상한(0.3 m/s)조차 이보다 작다 —
        // 즉 "이 속도로는 이 지형에서 해가 없다"는 물리적으로 정확한 상황이다.
        // 역방향 추적 중 속도가 뒤집혀 위치가 공 반대쪽으로 표류하다가 종료선에
        // 끝내 도달하지 못하고 nil을 반환하는 것이 올바른 동작이다 — 이 값을
        // 억지로 근사 후보로 보정하려는 시도는 검토 결과 기각되었다(반사가 일어나면
        // 위치가 종료선을 향해서가 아니라 반대 방향으로 표류하므로, 종료 지점에서의
        // 사후 보정 자체가 실행될 기회가 없다).
        let store = TerrainSampleStore()
        let nearThresholdNormal = simd_normalize(simd_float3(0.06, 1, 0))
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: nearThresholdNormal)
                z += 0.2
            }
            x += 0.2
        }
        let finder = PuttRangeFinder(terrain: store)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.3)

        XCTAssertNil(candidate, "물리적 최소 통과속도보다 작은 목표는 이 지형에서 해가 없다 — nil이 올바른 결과다")
    }
}

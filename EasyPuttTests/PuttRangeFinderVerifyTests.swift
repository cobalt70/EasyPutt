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
}

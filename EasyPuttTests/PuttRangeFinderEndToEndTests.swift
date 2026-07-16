import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderEndToEndTests: XCTestCase {

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

    func testFindSolutionsReturnsAtLeastOneVerifiedSolution() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let solutions = finder.findSolutions(ballPosition: ball, holePosition: hole)

        XCTAssertFalse(solutions.isEmpty, "완만한 직선 내리막 지형에서는 최소 하나의 해가 나와야 한다")
        for solution in solutions {
            XCTAssertGreaterThan(solution.direction.x, 0.8, "이 지형에서 해는 대체로 +x(홀컵) 방향을 향해야 한다")
        }
    }

    func testFindSolutionsReturnsEmptyWithoutTerrainData() {
        let finder = PuttRangeFinder(terrain: TerrainSampleStore())
        let solutions = finder.findSolutions(ballPosition: simd_float3(-1, 0, 0), holePosition: simd_float3(1.5, 0, 0))
        XCTAssertTrue(solutions.isEmpty)
    }
}

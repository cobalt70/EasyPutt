import XCTest
import simd
@testable import EasyPutt

final class TerrainSampleStoreTests: XCTestCase {

    func testEmptyStoreReturnsNil() {
        let store = TerrainSampleStore()
        XCTAssertNil(store.nearestNormal(to: .zero))
        XCTAssertTrue(store.isEmpty)
    }

    func testReturnsNearestSampleByHorizontalDistance() {
        let store = TerrainSampleStore()
        store.add(position: simd_float3(0, 0, 0), normal: simd_float3(0, 1, 0))
        store.add(position: simd_float3(10, 0, 0), normal: simd_float3(1, 0, 0))

        let result = store.nearestNormal(to: simd_float3(9.8, 5, 0))

        XCTAssertEqual(result, simd_float3(1, 0, 0))
    }

    func testIgnoresHeightDifferenceWhenFindingNearest() {
        let store = TerrainSampleStore()
        store.add(position: simd_float3(0, 100, 0), normal: simd_float3(0, 1, 0))
        store.add(position: simd_float3(1, 0, 0), normal: simd_float3(1, 0, 0))

        // (0, 100, 0) is horizontally (XZ) closer to the query point than (1, 0, 0),
        // even though it is far away vertically.
        let result = store.nearestNormal(to: simd_float3(0.1, 0, 0))

        XCTAssertEqual(result, simd_float3(0, 1, 0))
    }

    func testCountIsEmptyAndRemoveAll() {
        let store = TerrainSampleStore()
        XCTAssertEqual(store.count, 0)
        store.add(position: .zero, normal: simd_float3(0, 1, 0))
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.isEmpty)
        store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.isEmpty)
    }

    func testReturnsNearestSampleEvenWhenFar() {
        let store = TerrainSampleStore()
        store.add(position: simd_float3(0, 0, 0), normal: simd_float3(0, 1, 0))

        // Only sample is 10m away horizontally — still the best estimate available.
        let result = store.nearestNormal(to: simd_float3(10, 0, 0))

        XCTAssertEqual(result, simd_float3(0, 1, 0))
    }
}

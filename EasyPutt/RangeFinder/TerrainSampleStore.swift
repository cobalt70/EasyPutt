//
//  TerrainSampleStore.swift
//  EasyPutt
//

import simd

struct TerrainSample {
    let position: simd_float3
    let normal: simd_float3
}

/// 공~홀컵 사이에서 수집한 (좌표, 법선벡터) 샘플의 원시 리스트.
/// 별도의 격자/평면 클러스터링 없이, 질의 지점에서 수평(XZ) 거리 기준으로
/// 가장 가까운 샘플 하나의 법선벡터를 그대로 반환한다.
final class TerrainSampleStore {
    private(set) var samples: [TerrainSample] = []

    /// 질의 지점에서 가장 가까운 샘플까지의 거리가 이 값을 넘으면 nil을 반환한다 —
    /// 실제 스캔은 손으로 든 카메라로 듬성듬성 수집되므로, 커버되지 않은 지점에서
    /// 엉뚱하게 먼 샘플의 법선벡터를 반환하는 대신 "모른다"고 답해야 한다.
    /// 기본값은 ArViewModel의 terrainSampleMinSpacing(수집 버스트 간 최소 카메라 이동
    /// 거리)과 같은 척도로 맞췄다.
    var maxDistance: Float = 0.5

    var isEmpty: Bool { samples.isEmpty }
    var count: Int { samples.count }

    func add(position: simd_float3, normal: simd_float3) {
        samples.append(TerrainSample(position: position, normal: simd_normalize(normal)))
    }

    func removeAll() {
        samples.removeAll()
    }

    func nearestNormal(to position: simd_float3) -> simd_float3? {
        guard !samples.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistanceSquared = horizontalDistanceSquared(position, samples[0].position)
        for index in 1..<samples.count {
            let distanceSquared = horizontalDistanceSquared(position, samples[index].position)
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestIndex = index
            }
        }
        guard bestDistanceSquared <= maxDistance * maxDistance else { return nil }
        return samples[bestIndex].normal
    }

    private func horizontalDistanceSquared(_ a: simd_float3, _ b: simd_float3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}

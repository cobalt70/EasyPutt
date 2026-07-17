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

    var isEmpty: Bool { samples.isEmpty }
    var count: Int { samples.count }

    func add(position: simd_float3, normal: simd_float3) {
        samples.append(TerrainSample(position: position, normal: simd_normalize(normal)))
    }

    func removeAll() {
        samples.removeAll()
    }

    /// 가장 가까운 샘플의 법선벡터를 거리 제한 없이 반환한다 — 스캔이 듬성듬성해서
    /// 근처에 샘플이 없더라도, 있는 것 중 가장 가까운 값을 최선의 추정치로 쓴다.
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
        return samples[bestIndex].normal
    }

    private func horizontalDistanceSquared(_ a: simd_float3, _ b: simd_float3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}

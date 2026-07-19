//
//  TerrainSampleStore.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 7/16/26.
//  Updated by Gi Woo Kim on 7/19/26.
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
        nearestSample(to: position)?.normal
    }

    /// 가장 가까운 샘플의 실제 좌표(높이 포함)를 반환한다 — 지형이 없는 지점의 높이를
    /// 추정할 때(예: 시각화용 직선의 도착점 높이) 쓴다.
    func nearestPosition(to position: simd_float3) -> simd_float3? {
        nearestSample(to: position)?.position
    }

    private func nearestSample(to position: simd_float3) -> TerrainSample? {
        guard !samples.isEmpty else { return nil }
        var best = samples[0]
        var bestDistanceSquared = horizontalDistanceSquared(position, best.position)
        for sample in samples.dropFirst() {
            let distanceSquared = horizontalDistanceSquared(position, sample.position)
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                best = sample
            }
        }
        return best
    }

    private func horizontalDistanceSquared(_ a: simd_float3, _ b: simd_float3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}

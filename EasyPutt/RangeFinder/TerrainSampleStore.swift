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

    /// 최근접 샘플에서 이만큼 이내에 있는 이웃까지 법선 평균에 포함한다 — 3x3 수집 패치의
    /// 실제 샘플 간격(terrainSampleMinSpacing=0.3m 수준)을 덮는 크기.
    private let neighborAveragingMargin: Float = 0.5

    /// 가장 가까운 샘플의 법선을 거리 제한 없이 쓰되, 최근접과 비슷한 거리
    /// (+neighborAveragingMargin 이내)의 이웃 법선들을 평균해 반환한다 — 최근접 하나만
    /// 쓰면 수집 게이트(45도)를 통과한 아웃라이어 샘플 하나가 그 주변 물리를 통째로
    /// 지배하는데, 평균을 내면 그 영향이 이웃 수만큼 희석된다. 저장된 법선은 전부
    /// 단위벡터이므로 합을 다시 정규화하면 결과도 단위벡터다.
    func nearestNormal(to position: simd_float3) -> simd_float3? {
        nearestSurface(to: position)?.normal
    }

    /// nearestNormal과 같은 이웃 집합에서, 법선 평균과 지면 높이(이웃 샘플 위치의 y 평균)를
    /// 한 번의 스캔으로 함께 반환한다 — 법선을 이웃 평균으로 보정했으면, 그 법선을 쓰는
    /// 지점의 높이도 같은 이웃들의 높이로 보정하는 게 일관적이다(시뮬레이션 스텝마다
    /// 공의 y를 이 값으로 스냅해 궤적이 실제 지면에서 떠오르거나 파묻히는 표류를 막는다).
    func nearestSurface(to position: simd_float3) -> (normal: simd_float3, height: Float)? {
        guard let nearest = nearestSample(to: position) else { return nil }
        let radius = horizontalDistanceSquared(position, nearest.position).squareRoot() + neighborAveragingMargin
        let radiusSquared = radius * radius
        var sum = simd_float3.zero
        var heightSum: Float = 0
        var count = 0
        for sample in samples where horizontalDistanceSquared(position, sample.position) <= radiusSquared {
            sum += sample.normal
            heightSum += sample.position.y
            count += 1
        }
        let height = heightSum / Float(count)
        let length = simd_length(sum)
        guard length > 0.0001 else { return (nearest.normal, height) }
        return (sum / length, height)
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

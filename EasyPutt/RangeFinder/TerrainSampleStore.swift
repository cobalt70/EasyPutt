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

    /// 백그라운드 솔버가 읽는 동안 Reset 등이 원본을 비워도 안전하도록, 솔버에 넘길
    /// 스냅샷 복사본을 만든다 (samples는 값 타입 배열이라 통째 대입이 곧 복사다).
    func snapshot() -> TerrainSampleStore {
        let copy = TerrainSampleStore()
        copy.samples = samples
        return copy
    }

    /// 최근접 샘플에서 이만큼 이내에 있는 이웃까지 최빈 클러스터 후보에 포함한다 —
    /// 3x3 수집 패치의 실제 샘플 간격(terrainSampleMinSpacing=0.3m 수준)을 덮는 크기.
    private let neighborAveragingMargin: Float = 0.5

    /// 이 각도 이내로 비슷한 법선은 "같은 법선"으로 묶는다 — 그린의 실제 기울기 변화와
    /// 센서 노이즈는 몇 도 수준이고, 45도 게이트를 통과한 아웃라이어는 보통 이보다 크게
    /// 어긋나므로 무리에 못 끼고 탈락한다.
    private let modeAngleToleranceCosine: Float = cos(10 * Float.pi / 180)

    /// 질의 지점 주변 이웃들의 최빈(mode) 법선을 반환한다 — nearestSurface 참고.
    func nearestNormal(to position: simd_float3) -> simd_float3? {
        nearestSurface(to: position)?.normal
    }

    /// 최근접과 비슷한 거리(+neighborAveragingMargin 이내)의 이웃들을 모은 뒤, 법선이
    /// 허용 각도(modeAngleToleranceCosine) 이내로 비슷한 것끼리 무리 지어 가장 빈도가
    /// 높은 무리(최빈 클러스터)의 평균 법선과 평균 높이를 반환한다. 단순 평균은
    /// 아웃라이어도 1/k만큼 결과를 끌어당기지만, 최빈 무리를 고르면 소수 아웃라이어는
    /// 무리에 못 끼어 결과에 아예 영향을 못 준다. 동률이면 질의 지점에 더 가까운 샘플이
    /// 이끄는 무리가 이긴다. 높이도 같은(이긴) 무리의 샘플들에서만 평균한다 —
    /// 법선과 높이가 같은 지면 추정에서 나오도록(시뮬레이션 스텝마다 공의 y를 이 값으로
    /// 스냅해 궤적이 실제 지면에서 떠오르거나 파묻히는 표류를 막는다).
    func nearestSurface(to position: simd_float3) -> (normal: simd_float3, height: Float)? {
        guard let nearest = nearestSample(to: position) else { return nil }
        let radius = horizontalDistanceSquared(position, nearest.position).squareRoot() + neighborAveragingMargin
        let radiusSquared = radius * radius
        var neighbors = samples.filter { horizontalDistanceSquared(position, $0.position) <= radiusSquared }
        neighbors.sort { horizontalDistanceSquared(position, $0.position) < horizontalDistanceSquared(position, $1.position) }

        var bestGroup: [TerrainSample] = []
        for center in neighbors {
            let group = neighbors.filter { simd_dot($0.normal, center.normal) >= modeAngleToleranceCosine }
            if group.count > bestGroup.count {
                bestGroup = group
            }
        }

        var sum = simd_float3.zero
        var heightSum: Float = 0
        for sample in bestGroup {
            sum += sample.normal
            heightSum += sample.position.y
        }
        let height = heightSum / Float(bestGroup.count)
        // 무리 안 법선들은 서로 10도 이내라 합이 0이 될 수 없다 — 정규화만 하면 단위벡터.
        return (simd_normalize(sum), height)
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

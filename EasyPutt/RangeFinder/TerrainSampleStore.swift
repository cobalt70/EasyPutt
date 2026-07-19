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

    /// 질의 지점 주변 이웃들의 평균 법선을 반환한다 — nearestSurface 참고.
    func nearestNormal(to position: simd_float3) -> simd_float3? {
        nearestSurface(to: position)?.normal
    }

    /// 최근접과 비슷한 거리(+neighborAveragingMargin 이내)의 이웃 법선/높이를 평균해
    /// 반환한다. 아웃라이어 제거(45도 게이트 + 20도 상호 합의)는 수집 시점에 이미
    /// 끝났으므로 여기서는 단순 평균으로 충분하다 — 이 함수는 시뮬레이션 매 스텝 불리기
    /// 때문에 할당 없는 선형 스캔이어야 한다(한때 여기서 최빈 클러스터링을 했더니 스텝마다
    /// 정렬+O(k²)+배열 할당이 누적돼 솔버가 0.3초에서 15초로 느려졌다).
    /// 높이도 같은 이웃들의 평균이다 — 법선과 높이가 같은 지면 추정에서 나오도록
    /// (시뮬레이션 스텝마다 공의 y를 이 값으로 스냅해 궤적의 높이 표류를 막는다).
    func nearestSurface(to position: simd_float3) -> (normal: simd_float3, height: Float)? {
        guard !samples.isEmpty else { return nil }
        var nearestDistanceSquared = Float.greatestFiniteMagnitude
        for sample in samples {
            let distanceSquared = horizontalDistanceSquared(position, sample.position)
            if distanceSquared < nearestDistanceSquared {
                nearestDistanceSquared = distanceSquared
            }
        }
        let radius = nearestDistanceSquared.squareRoot() + neighborAveragingMargin
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
        // 저장된 법선은 전부 45도 게이트를 통과한 단위벡터라 y성분이 모두 양수 —
        // 합이 0이 될 수 없으므로 정규화만 하면 된다.
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

//
//  PuttRangeFinder.swift
//  EasyPutt
//

import simd

/// 성공(홀인 가능)으로 판정된 하나의 (방향, 속도) 조합.
struct PuttSolution {
    let direction: simd_float3 // 수평 단위벡터
    let speed: Float
}

struct PuttRangeFinderConfig {
    var rollingResistance: Float = 0.35
    var deltaTime: Float = 0.05
    var maxBackwardSteps: Int = 4000
    var maxForwardSteps: Int = 4000
    /// 홀인으로 판정하는 최대 허용 오차 — 홀컵 반경(≈5.4cm) - 공 반지름(2.135cm).
    var captureRadius: Float = 0.033
    /// 백워드 추적을 시작할 때 가정하는, 홀컵을 통과하는 속도의 스윕 값들.
    var holeCrossingSpeeds: [Float] = [0.03, 0.05, 0.08, 0.11, 0.14]
    var maxCorrectionIterations: Int = 15
    /// 정밀검증 보정 반복에서 옆으로 빗나간 정도(m)에 대한 방향 보정 계수(rad/m).
    var directionGain: Float = 0.5
    /// 정밀검증 보정 반복에서 못미치거나 지나친 정도(m)에 대한 속도 보정 계수((m/s)/m).
    var speedGain: Float = 0.3
    /// 홀컵에서의 최대 경사(steepestDescentDirection)가 공→홀컵 직선과 이루는 각의 코사인
    /// 임계값. 이 값보다 정렬이 나쁘면(기본값 0.5 = 60도보다 더 벌어지면 — 예: 오르막
    /// 퍼팅처럼 최대 경사 방향이 공 반대쪽을 향하는 경우) 최대 경사 대신 공→홀컵 직선
    /// 자체를 백워드 시작 방향으로 쓴다.
    var naturalDirectionAlignmentThreshold: Float = 0.5

    static let `default` = PuttRangeFinderConfig()
}

final class PuttRangeFinder {
    private let terrain: TerrainSampleStore
    private let config: PuttRangeFinderConfig

    init(terrain: TerrainSampleStore, config: PuttRangeFinderConfig = .default) {
        self.terrain = terrain
        self.config = config
    }

    /// 홀컵에서 공 쪽으로 거슬러 올라가며 초기 후보 (방향, 속도)를 구한다.
    /// 공-홀컵 직선에 수직이고 공 위치를 지나는 선을 넘으면(또는 지형 데이터가
    /// 없거나 속도가 0 이하가 되면) 종료하고, 그 시점의 상태를 후보로 반환한다.
    /// 시작 방향은 원칙적으로 홀컵에서의 최대 경사(steepestDescentDirection)를 쓰지만,
    /// 그 방향이 공→홀컵 직선과 `naturalDirectionAlignmentThreshold`보다 더 벌어지면
    /// (평지이거나, 오르막 퍼팅처럼 최대 경사가 공 반대쪽을 향하는 경우) 공→홀컵 직선
    /// 자체로 대체한다 — "뒤쪽"(공에서 60도 넘게 벗어난 방향)에서 후보를 찾지 않는다.
    /// 이 결과는 근사치이며 최종 정답이 아니다 — `verify(_:ballPosition:holePosition:)`로 보정해야 한다.
    func backwardCandidate(holePosition: simd_float3, ballPosition: simd_float3, holeCrossingSpeed: Float) -> PuttSolution? {
        guard holeCrossingSpeed > 0 else { return nil }
        guard let holeNormal = terrain.nearestNormal(to: holePosition) else { return nil }

        let toBall = ballPosition - holePosition
        let toBallHorizontal = simd_float3(toBall.x, 0, toBall.z)
        let ballAxisDistance = simd_length(toBallHorizontal)
        guard ballAxisDistance > 0.0001 else { return nil }
        let toBallUnit = toBallHorizontal / ballAxisDistance
        // 홀컵→공 반대 방향, 즉 "공에서 홀컵을 향해 친다"는 직선 방향.
        let straightLineDirection = -toBallUnit

        var initialDirection = GolfBall.steepestDescentDirection(surfaceNormal: holeNormal)
        if simd_dot(initialDirection, straightLineDirection) < config.naturalDirectionAlignmentThreshold {
            initialDirection = straightLineDirection
        }

        let ball = GolfBall(initialPosition: holePosition, initialVelocity: initialDirection * holeCrossingSpeed)
        ball.rollingResistance = config.rollingResistance

        for _ in 0..<config.maxBackwardSteps {
            guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
            ball.updateFromTorque(deltaTime: -config.deltaTime, surfaceNormal: normal)

            let progress = simd_dot(
                simd_float3(ball.position.x - holePosition.x, 0, ball.position.z - holePosition.z),
                toBallUnit
            )
            if progress >= ballAxisDistance {
                let horizontalVelocity = simd_float3(ball.velocity.x, 0, ball.velocity.z)
                let speed = simd_length(horizontalVelocity)
                guard speed > 0.0001 else { return nil }
                return PuttSolution(direction: horizontalVelocity / speed, speed: speed)
            }
            if simd_length(ball.velocity) < 0.0001 { return nil }
        }
        return nil
    }
}

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
    /// 실제 "다잉 퍼팅"(홀컵을 겨우 넘기는 정도의 세기) 통과속도 범위(0.1~0.3 m/s)를 따른다.
    var holeCrossingSpeeds: [Float] = [0.1, 0.15, 0.2, 0.25, 0.3]
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
    /// 경사가 구름저항보다 강한 지형에서 holeCrossingSpeed가 그 지형/거리로는
    /// 물리적으로 실현 불가능할 만큼 작으면(예: 아주 가파른 그린), 역방향 추적
    /// 중 속도가 0을 지나 반대 방향으로 뒤집히면서 위치가 공이 아니라 반대쪽으로
    /// 표류한다 — 이 경우 종료선에 도달하지 못하고 nil을 반환한다. 이는 계산
    /// 오류가 아니라 "이 속도로는 해가 없다"는 정상적인 신호다(실제 그린의
    /// 90% 이상은 경사가 3% 미만이라 이 상황 자체가 거의 발생하지 않는다).
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

    /// `candidate`를 실제 정방향 물리 엔진으로 재시뮬레이션하고, 홀컵과의
    /// 최근접 거리(오차)를 이용해 (speed, direction)을 반복 보정한다.
    /// 캡처 반경 이내로 수렴하면 그 candidate를 반환하고, `maxCorrectionIterations`
    /// 내에 수렴하지 못하면 nil을 반환한다.
    func verify(_ initialCandidate: PuttSolution, ballPosition: simd_float3, holePosition: simd_float3) -> PuttSolution? {
        var candidate = initialCandidate

        for _ in 0..<config.maxCorrectionIterations {
            guard let result = simulateForward(candidate, from: ballPosition, holePosition: holePosition) else {
                return nil
            }
            if result.closestDistance <= config.captureRadius {
                return candidate
            }
            candidate = correct(candidate, ballPosition: ballPosition, holePosition: holePosition, result: result)
        }
        return nil
    }

    /// 여러 홀컵 통과속도를 스윕하며 백워드 후보를 만들고, 각 후보를 검증해서
    /// 캡처 반경 이내로 수렴하는 (direction, speed) 조합들을 모두 반환한다.
    /// 성공하는 방향들이 하나의 연속 구간이 아니라 여러 구간으로 나올 수 있으므로,
    /// 병합하지 않고 있는 그대로 반환한다.
    func findSolutions(ballPosition: simd_float3, holePosition: simd_float3) -> [PuttSolution] {
        var solutions: [PuttSolution] = []
        for crossingSpeed in config.holeCrossingSpeeds {
            guard let candidate = backwardCandidate(
                holePosition: holePosition,
                ballPosition: ballPosition,
                holeCrossingSpeed: crossingSpeed
            ) else { continue }

            if let verified = verify(candidate, ballPosition: ballPosition, holePosition: holePosition) {
                solutions.append(verified)
            }
        }
        return solutions
    }

    private struct ForwardSimulationResult {
        let closestPosition: simd_float3
        let closestDistance: Float
    }

    private func simulateForward(_ candidate: PuttSolution, from ballPosition: simd_float3, holePosition: simd_float3) -> ForwardSimulationResult? {
        let ball = GolfBall(initialPosition: ballPosition, initialVelocity: candidate.direction * candidate.speed)
        ball.rollingResistance = config.rollingResistance

        var closestPosition = ballPosition
        var closestDistance = horizontalDistance(ballPosition, holePosition)

        for _ in 0..<config.maxForwardSteps {
            guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
            ball.updateFromTorque(deltaTime: config.deltaTime, surfaceNormal: normal)

            let distance = horizontalDistance(ball.position, holePosition)
            if distance < closestDistance {
                closestDistance = distance
                closestPosition = ball.position
            }
            if ball.hasStopped { break }
        }
        return ForwardSimulationResult(closestPosition: closestPosition, closestDistance: closestDistance)
    }

    private func correct(_ candidate: PuttSolution, ballPosition: simd_float3, holePosition: simd_float3, result: ForwardSimulationResult) -> PuttSolution {
        let toHole = holePosition - ballPosition
        let toHoleHorizontal = simd_float3(toHole.x, 0, toHole.z)
        guard simd_length(toHoleHorizontal) > 0.0001 else { return candidate }
        let toHoleUnit = simd_normalize(toHoleHorizontal)
        let sideways = simd_float3(-toHoleUnit.z, 0, toHoleUnit.x)

        let missVector = simd_float3(
            result.closestPosition.x - holePosition.x, 0,
            result.closestPosition.z - holePosition.z
        )
        let lateralMiss = simd_dot(missVector, sideways)
        let alongMiss = simd_dot(missVector, toHoleUnit)

        let angleCorrection = -lateralMiss * config.directionGain
        let speedCorrection = -alongMiss * config.speedGain

        let correctedDirection = simd_normalize(rotateHorizontal(candidate.direction, by: angleCorrection))
        let correctedSpeed = max(0.05, candidate.speed + speedCorrection)
        return PuttSolution(direction: correctedDirection, speed: correctedSpeed)
    }

    private func rotateHorizontal(_ v: simd_float3, by angle: Float) -> simd_float3 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float3(v.x * c - v.z * s, v.y, v.x * s + v.z * c)
    }

    private func horizontalDistance(_ a: simd_float3, _ b: simd_float3) -> Float {
        simd_distance(simd_float3(a.x, 0, a.z), simd_float3(b.x, 0, b.z))
    }
}

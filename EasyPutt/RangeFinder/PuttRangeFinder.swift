//
//  PuttRangeFinder.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 7/16/26.
//  Updated by Gi Woo Kim on 7/19/26.
//

import simd

/// 성공(홀인 가능)으로 판정된 하나의 (방향, 속도) 조합.
struct PuttSolution {
    let direction: simd_float3 // 수평 단위벡터
    let speed: Float
    /// verify()가 성공했을 때의 정방향 시뮬레이션 경로(5스텝마다 다운샘플링, 마지막
    /// 기록은 항상 공이 멈춘 지점). 시각화 용도이며, backwardCandidate()가 만드는
    /// 근사 후보나 verify()의 중간 보정 후보에는 채워지지 않는다(빈 배열).
    var path: [simd_float3] = []
    /// 같은 속도(speed)는 유지한 채 방향(좌우 각도)만 틀어도 여전히 홀에 들어가는
    /// 각도 범위의 두 경계 방향벡터 — directionBoundaryA는 항상 왼쪽(더 작은/음수 쪽),
    /// directionBoundaryB는 항상 오른쪽(더 큰/양수 쪽)이다(puttRelative() 기준).
    var directionBoundaryA: simd_float3?
    var directionBoundaryB: simd_float3?
    /// directionBoundaryA/B 방향으로 쳤을 때의 정방향 시뮬레이션 경로 — 시각화에서
    /// "이 두 경계 사이로 치면 들어간다"는 걸 보여주기 위함. path와 같은 다운샘플링 규칙.
    var boundaryAPath: [simd_float3] = []
    var boundaryBPath: [simd_float3] = []
}

struct PuttRangeFinderConfig {
    var rollingResistance: Float = 0.35
    /// 짧은 퍼트(1m 이내)는 스텝당 이동거리가 캡처 반경(3.3cm)보다 커질 수 있어
    /// (예: 0.05초 스텝에서 속도 1m/s면 스텝당 5cm) directionRange의 좌우 경계 탐색이
    /// "운 좋게 한 스텝만 홀에 걸리는" 이산화 오차로 왜곡될 수 있다 — deltaTime을
    /// 작게 잡아 스텝 간격을 캡처 반경보다 충분히 촘촘하게 만든다.
    var deltaTime: Float = 0.01
    var maxBackwardSteps: Int = 1000
    var maxForwardSteps: Int = 1000
    /// 홀인으로 판정하는 최대 허용 오차 — 홀컵 반경(≈5.4cm) 그 자체. 공 전체가 완전히
    /// 홀 위에 떠야(반경-공반지름) 캡처된다고 보는 건 틀렸다 — 공의 무게중심이 홀 반경
    /// 안(허공 위)으로 들어오는 순간, 가장자리 일부가 아직 테두리에 걸쳐있어도 그 접촉은
    /// 무게를 못 버티고 중력에 져서 기울며 떨어진다. 그러니까 지지를 잃는 기준은 공
    /// 중심이 홀 반경 안으로 들어오는 시점 그 자체다.
    var captureRadius: Float = 0.054
    /// 홀컵을 놓쳤을 때 이 정도만 지나쳐서 멈추는 세기(다잉 퍼팅)를 목표로 삼는다.
    /// 실제 골프에서 흔히 말하는 "10~30cm 지나치는 세기"의 중간값.
    var targetOverrunDistance: Float = 0.2
    /// 백워드 추적을 시작할 때 가정하는, 홀컵을 통과하는 속도 — targetOverrunDistance를
    /// rollingResistance(그린 스피드)에 맞춰 v = sqrt(2 × rollingResistance × 거리)로
    /// 역산한다. 그린이 빠르면(rollingResistance 작음) 더 낮은 속도로도 같은 거리를
    /// 지나치므로, 이 값도 자동으로 같이 낮아진다.
    var holeCrossingSpeeds: [Float] {
        [(2 * rollingResistance * targetOverrunDistance).squareRoot()]
    }
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
                return PuttSolution(direction: candidate.direction, speed: candidate.speed, path: result.path)
            }
            candidate = correct(candidate, ballPosition: ballPosition, holePosition: holePosition, result: result)
        }
        return nil
    }

    /// 백워드 전용 탐색(backwardOnlySolve)이 구한 해를 시드로 삼아, forward 시뮬레이션으로
    /// 검증/보정한다 — B(백워드 전용 탐색)와 B+F(이 함수)가 "초기 해를 찾는 방식과 가정"을
    /// 공유하도록 통일했다: B는 그 탐색 결과를 그대로 쓰고, B+F는 같은 결과를 시작점 삼아
    /// forward 보정만 얹는다. 예전에는 backwardCandidate()의 단순 추측(최대경사 또는 직선,
    /// 단일 시도)을 시드로 썼는데, 이제 B 쪽에서 이미 검증한(양방향 탐색 + 데드존 안전) 훨씬
    /// 정확한 시드를 그대로 재사용하므로 verify()가 처리해야 할 보정량도 줄어든다.
    ///
    /// backwardOnlySolve가 nil이면(예: 미끄럼 구간 마찰 때문에 그 안의 고정 overrun
    /// 래더로는 어느 것도 forward 검증을 통과 못 하는 완만한 경사) backwardCandidate()의
    /// 단순 근사 시드로 대체한다 — B는 forward 보정이 없어 이 상황에서 정말로 해를 못
    /// 찾은 것으로 보는 게 맞지만(그래서 backwardOnlySolve 자체는 안 건드린다), B+F는
    /// 원래도 verify()의 반복 보정을 갖고 있으니 시드가 덜 정확해도 그 보정으로 수렴할
    /// 여지가 있다 — B+F가 B보다 못한 결과(해를 못 찾음)를 내는 걸 막는다.
    func findSolutions(ballPosition: simd_float3, holePosition: simd_float3) -> [PuttSolution] {
        var solutions: [PuttSolution] = []
        let candidate = backwardOnlySolve(ballPosition: ballPosition, holePosition: holePosition)
            ?? config.holeCrossingSpeeds.lazy.compactMap {
                self.backwardCandidate(holePosition: holePosition, ballPosition: ballPosition, holeCrossingSpeed: $0)
            }.first
        guard let candidate else {
            return solutions
        }

        if var verified = verify(candidate, ballPosition: ballPosition, holePosition: holePosition) {
            if let range = directionRange(for: verified, ballPosition: ballPosition, holePosition: holePosition) {
                verified.directionBoundaryA = range.a
                verified.directionBoundaryB = range.b
                let boundaryA = PuttSolution(direction: range.a, speed: verified.speed)
                let boundaryB = PuttSolution(direction: range.b, speed: verified.speed)
                verified.boundaryAPath = simulateForward(boundaryA, from: ballPosition, holePosition: holePosition)?.path ?? []
                verified.boundaryBPath = simulateForward(boundaryB, from: ballPosition, holePosition: holePosition)?.path ?? []
            }
            solutions.append(verified)
        }
        return solutions
    }

    /// forward 시뮬레이션(verify/correct)을 전혀 쓰지 않고, 백워드 추적 + 이분탐색만으로
    /// 해와 좌우 범위를 직접 구한다. holeCrossingSpeeds 각각에 대해 backwardOnlySolve를
    /// 호출한다 — findSolutions()와 대응되는 "백워드 전용" 버전.
    func findSolutionsBackwardOnly(ballPosition: simd_float3, holePosition: simd_float3) -> [PuttSolution] {
        guard let solution = backwardOnlySolve(ballPosition: ballPosition, holePosition: holePosition) else { return [] }
        return [solution]
    }

    /// 홀→공 직선을 탐색 기준각(0도)으로 삼는다. 각 테스트 각도로 홀에서 백워드 추적해
    /// "공의 출발선"(공을 지나고 홀-공 직선에 수직인 선)에 도달하는 지점이 실제 공 위치에서
    /// 좌우로 얼마나(부호 있게) 벗어나는지를 판정 기준으로 쓴다. 0도에서 시작해 그 부호를
    /// 줄이는 방향으로 coarseAngleStep씩(탐색 시작→끝) 넓혀가며 부호가 뒤집히는 지점을 찾은
    /// 뒤, 그 구간에서 이분탐색으로 좁힌다 — 양 끝 각도(예: ±89도)가 미리 둘 다 유효한
    /// 추적이어야 한다는 조건 없이도 안전하게 수렴한다(각도가 클수록 홀에서 거의 옆으로
    /// 쏘는 셈이라 추적이 중간에 끊길 수 있는데, 그 경우 그 지점 이전까지만 탐색한다).
    /// target=0은 공을 정확히 맞히는 중앙 해, target=±captureRadius는 홀컵에 겨우 걸치는
    /// 좌우 경계 — forward 시뮬레이션으로 검증하지 않으므로 verify()/correct()보다 빠르지만,
    /// 근사 없이 물리 파라미터(구름저항)만으로 수렴하는 값이라 결과가 다를 수 있다. 시각화
    /// 경로도 이 백워드 추적 경로를 그대로(홀→공을 공→홀 순서로 뒤집어) 채운다.
    private func backwardOnlySolve(
        ballPosition: simd_float3,
        holePosition: simd_float3,
        coarseAngleStep: Float = (Float.pi / 180) * 1.0,
        // 60도까지만 훑는다 — backwardCandidate가 이미 쓰는 naturalDirectionAlignmentThreshold
        // (cos 60도)와 같은 한계다. 60도 근처는 전진 속도 성분이 작아(cos60°=0.5) maxBackwardSteps
        // 예산 안에서도 충분히 먼 거리까지 커버되지만, 89도까지 가면 그 여유가 크게 줄어든다.
        maxCoarseSteps: Int = 60,
        bisectionIterations: Int = 24
    ) -> PuttSolution? {
        let toBall = ballPosition - holePosition
        let toBallHorizontal = simd_float3(toBall.x, 0, toBall.z)
        let ballAxisDistance = simd_length(toBallHorizontal)
        guard ballAxisDistance > 0.0001 else { return nil }
        let toBallUnit = toBallHorizontal / ballAxisDistance
        let forwardAxis = -toBallUnit
        let rightAxis = simd_float3(-forwardAxis.z, 0, forwardAxis.x)

        // 홀컵을 지나는 속도가 너무 약하면(overrun 거리가 작으면) 역방향 적분 중 가파른
        // 지형에서 속도가 죽어 0도조차 공의 출발선에 못 닿을 수 있다 — traceBackward가
        // 참조하는 crossingSpeed를 var로 두고, 작은 overrun부터 시도하다 중앙 해를 못
        // 찾으면 더 큰 값(더 센 시작 속도)으로 처음부터 다시(coarse walk 포함) 시도한다.
        var crossingSpeed: Float = 0

        struct BackwardTrace {
            let angle: Float
            let crossingPosition: simd_float3
            let velocity: simd_float3
            let path: [simd_float3] // 홀→공 순서, 5스텝마다 다운샘플링
        }

        func traceBackward(angle: Float) -> BackwardTrace? {
            let direction = rotateHorizontal(forwardAxis, by: angle)
            let ball = GolfBall(initialPosition: holePosition, initialVelocity: direction * crossingSpeed)
            ball.rollingResistance = config.rollingResistance
            var path: [simd_float3] = [holePosition]
            var previousPosition = holePosition
            var previousProgress: Float = 0

            for step in 0..<config.maxBackwardSteps {
                guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
                ball.updateFromTorque(deltaTime: -config.deltaTime, surfaceNormal: normal)

                // 이번 스텝이 그린 실제 경로(직전~다음 위치) 선분이 공 위치에서 0.5cm 이내로
                // 지나가면, 그 선분 위 최근접점에서 공을 직접 맞힌 것으로 본다 — 공의 출발선
                // (무한선) 교차만 보는 것보다 더 엄밀한 판정이다.
                let (closestToBall, distanceToBall) = closestHorizontalPoint(from: previousPosition, to: ball.position, target: ballPosition)
                if distanceToBall <= 0.005 {
                    path.append(closestToBall)
                    return BackwardTrace(angle: angle, crossingPosition: closestToBall, velocity: ball.velocity, path: path)
                }

                let progress = simd_dot(
                    simd_float3(ball.position.x - holePosition.x, 0, ball.position.z - holePosition.z),
                    toBallUnit
                )
                if progress >= ballAxisDistance {
                    // 스텝 한 번에 선을 훌쩍 넘어버릴 수 있으니(각도가 클수록 전진 속도 성분이
                    // 작아 이런 일이 덜하지만, 그래도) 직전~다음 위치 사이를 선형보간해서
                    // 정확히 진행거리가 ballAxisDistance가 되는 지점을 구한다.
                    let denominator = progress - previousProgress
                    let t = denominator > 0.0001 ? (ballAxisDistance - previousProgress) / denominator : 1
                    let crossingPosition = previousPosition + (ball.position - previousPosition) * max(0, min(1, t))
                    path.append(crossingPosition)
                    return BackwardTrace(angle: angle, crossingPosition: crossingPosition, velocity: ball.velocity, path: path)
                }
                previousPosition = ball.position
                previousProgress = progress
                if step % 5 == 0 {
                    path.append(ball.position)
                }
                // 0.0001(사실상 정확히 0)보다 넉넉하게 잡는다 — 그 근처의 아주 작은 속도는
                // 방향이 부동소수점 오차에 지배돼 더 이상 물리적으로 의미가 없으니, 그런
                // 상태로 계속 적분하느니 여기서 깔끔하게 "이 각도는 안 됨"으로 처리한다.
                if simd_length(ball.velocity) < 0.005 { return nil }
            }
            return nil
        }

        func offset(at angle: Float, target: Float) -> (value: Float, trace: BackwardTrace)? {
            guard let trace = traceBackward(angle: angle) else { return nil }
            let miss = simd_float3(
                trace.crossingPosition.x - ballPosition.x, 0,
                trace.crossingPosition.z - ballPosition.z
            )
            return (simd_dot(miss, rightAxis) - target, trace)
        }

        // startAngle에서 프로브를 시작해 그 결과를 판정 기준(target)에 맞춰 탐색한다.
        // 중앙 해(target=0)는 0도에서 시작하지만, 좌우 경계(target=±captureRadius)는
        // 이미 구해둔 중앙 해의 각도에서 시작한다 — 매번 0도부터 다시 훑을 필요 없이,
        // 이미 정답 근처라는 걸 알고 있으니 거기서부터 살짝만 더 틀어보면 된다
        // (directionRange가 verify()로 구한 중앙 방향에서부터 경계를 찾아나가는 것과 같은 패턴).
        func solveAngle(target: Float, startAngle: Float = 0) -> BackwardTrace? {
            // startAngle 자체가(가파른 지형, 수치오차 등으로) 실패할 수 있다 — 이 경우 곧장
            // 포기하지 않고 양쪽으로 coarseAngleStep씩 넓혀가며 "처음으로 성공하는 각도"를
            // 찾는다. directionRange의 captures()가 실패를 "이 각도는 안 됨"으로만 처리하고
            // 탐색을 계속하는 것과 같은 원리 — 시작점 하나의 실패가 전체 탐색을 막으면 안 된다.
            var probeAngle = startAngle
            var probeOffset: Float
            var probeTrace: BackwardTrace
            if let (value, trace) = offset(at: startAngle, target: target) {
                probeOffset = value
                probeTrace = trace
            } else {
                var found: (angle: Float, value: Float, trace: BackwardTrace)?
                searchLoop: for step in 1...maxCoarseSteps {
                    for sign: Float in [1, -1] {
                        let angle = startAngle + sign * coarseAngleStep * Float(step)
                        if let (value, trace) = offset(at: angle, target: target) {
                            found = (angle, value, trace)
                            break searchLoop
                        }
                    }
                }
                guard let found else {
                    print("[백워드전용] target=\(target): \(startAngle * 180 / .pi)도 근방 \(maxCoarseSteps)도 범위 안에서 유효한 추적을 하나도 못 찾음")
                    return nil
                }
                print("[백워드전용] target=\(target): \(startAngle * 180 / .pi)도 실패, \(found.angle * 180 / .pi)도에서 첫 성공")
                probeAngle = found.angle
                probeOffset = found.value
                probeTrace = found.trace
            }

            // 수렴 허용치는 0.5cm — 선분-원 교차 판정(위 closestHorizontalPoint 체크)이
            // 이미 정밀하게 잡아주므로, 이 지름길 체크도 정확도를 우선한다.
            if abs(probeOffset) < 0.005 { return probeTrace }

            // 오프셋 부호만 보고 "이 방향으로 가면 뒤집힐 것"이라고 한쪽에 베팅하지 않는다 —
            // 그 가정(단조성)이 지형에 따라 틀릴 수 있고, 틀리면 진짜 해가 있는 반대쪽은
            // 아예 시도도 안 해보고 끝나버린다. 그래서 양쪽 방향을 번갈아 동시에 걸어가며
            // 어느 쪽이든 먼저 부호가 뒤집히는 지점을 쓴다.
            let lowIsPositive = probeOffset > 0
            // 각도뿐 아니라 그때의 offset값과 trace까지 같이 들고 있어야, 이분탐색이
            // 데드존(추적 실패 각도들)에 막혀도 이미 확인된 low를 재추적 없이 쓸 수 있다.
            var lastGood: [Float: (angle: Float, value: Float, trace: BackwardTrace)] = [
                1: (probeAngle, probeOffset, probeTrace),
                -1: (probeAngle, probeOffset, probeTrace)
            ]
            var bracket: (angle: Float, value: Float, trace: BackwardTrace)?
            var bracketSign: Float = 1

            searchLoop: for step in 1...maxCoarseSteps {
                for sign: Float in [1, -1] {
                    let angle = probeAngle + sign * coarseAngleStep * Float(step)
                    guard let (value, trace) = offset(at: angle, target: target) else {
                        continue // 이 방향은 여기서 끊겼을 뿐, 반대 방향은 계속 유효할 수 있다
                    }
                    if (value > 0) != lowIsPositive {
                        bracket = (angle, value, trace)
                        bracketSign = sign
                        break searchLoop
                    }
                    lastGood[sign] = (angle, value, trace)
                }
            }

            guard let bracket else {
                print("[백워드전용] target=\(target): \(probeAngle * 180 / .pi)도 기준 양쪽 \(maxCoarseSteps)도 안에 부호 반전 못 찾음(브라켓 실패)")
                return nil
            }

            let lowSeed = lastGood[bracketSign] ?? (probeAngle, probeOffset, probeTrace)
            var low = lowSeed.angle
            var high = bracket.angle

            // 이분탐색이 중간에 데드존을 만나 high 쪽이 미확정 값으로 잠식되더라도, 이미
            // 확인된 것 중 가장 좋은(|offset|이 가장 작은) 표본보다 나쁜 답은 절대 반환하지
            // 않는다 — bracket 자체가 확정된 해이므로 최소한 이걸로 시작한다.
            var bestTrace = bracket.trace
            var bestOffset = abs(bracket.value)
            if abs(lowSeed.value) < bestOffset {
                bestOffset = abs(lowSeed.value)
                bestTrace = lowSeed.trace
            }

            var deadZoneHits = 0
            for _ in 0..<bisectionIterations {
                let mid = (low + high) / 2
                if let (value, trace) = offset(at: mid, target: target) {
                    if abs(value) < bestOffset {
                        bestOffset = abs(value)
                        bestTrace = trace
                    }
                    if (value > 0) == lowIsPositive {
                        low = mid
                    } else {
                        high = mid
                    }
                } else {
                    // 확정 안 된 지점은 directionRange의 captures()가 실패를 "캡처 안 됨"으로
                    // 접는 것과 같은 원리로, 안전한 쪽(high 잠식)으로 접어서 계속 좁혀간다.
                    deadZoneHits += 1
                    high = mid
                }
            }
            if deadZoneHits > 0 {
                print("[백워드전용] target=\(target): 이분탐색 중 \(deadZoneHits)번 데드존(추적 실패)과 마주침 — 최종 \(bestTrace.angle * 180 / .pi)도(|offset|=\(bestOffset))로 수렴")
            }
            return bestTrace
        }

        // bestTrace는 "데드존을 만나도 절대 나빠지지 않는다"만 보장할 뿐, "충분히 정확하다"는
        // 보장은 아니다 — 데드존이 브라켓 전체를 거의 다 잠식하면 coarseAngleStep 수준의 거친
        // 정밀도로 남을 수 있다. 그런데 bestOffset(공 쪽 오차)이 홀 쪽 오차로 정확히 얼마나
        // 옮겨가는지는 지형마다 달라서 간접 추정이 부정확하다 — 대신 후보를 찾을 때마다
        // forward 시뮬레이션을 딱 한 번 돌려서 실제로 캡처 반경 안에 들어오는지 직접
        // 확인한다(verify()가 쓰는 것과 같은 진짜 판정 기준). 반복 보정이 아니라 최종
        // 검증 한 번이므로 "백워드 전용은 forward 시뮬레이션을 안 쓴다"는 원칙은 유지된다.
        let overrunCandidates: [Float] = [0.2, 0.3, 0.4, 0.5]
        var center: BackwardTrace?
        var verifiedPath: [simd_float3] = []
        for overrun in overrunCandidates {
            crossingSpeed = (2 * config.rollingResistance * overrun).squareRoot()
            guard crossingSpeed > 0.0001 else { continue }
            guard let found = solveAngle(target: 0) else {
                print("[백워드전용] overrun=\(overrun)m(crossingSpeed=\(crossingSpeed)) 중앙해 실패, 더 큰 값으로 재시도")
                continue
            }
            let foundSpeed = simd_length(found.velocity)
            guard foundSpeed > 0.0001 else { continue }
            let candidate = PuttSolution(direction: found.velocity / foundSpeed, speed: foundSpeed)
            guard let verification = simulateForward(candidate, from: ballPosition, holePosition: holePosition),
                  verification.closestDistance <= config.captureRadius else {
                print("[백워드전용] overrun=\(overrun)m: 중앙해는 찾았지만 forward 검증 실패(홀과 최근접 거리가 캡처 반경 밖) — 더 큰 값으로 재시도")
                continue
            }
            center = found
            // 화면에 보여줄 경로는 백워드로 되짚은 근사 경로가 아니라, 방금 검증에 실제로
            // 쓰인 forward 시뮬레이션 경로 그대로 쓴다 — "검증받은 것"과 "화면에 보이는 것"이
            // 다르면 안 된다.
            verifiedPath = verification.path
            break
        }
        guard let center else { return nil }
        let speed = simd_length(center.velocity)
        guard speed > 0.0001 else { return nil }

        var solution = PuttSolution(
            direction: center.velocity / speed,
            speed: speed,
            path: verifiedPath
        )

        // 경계는 추가 시뮬레이션 없이 순수 기하로 구한다 — captureRadius만큼 옆으로 비켜나는
        // 데 필요한 각도를 작은각 근사(atan(captureRadius/거리))로 구해서, 중앙 해의 최종
        // 방향벡터를 그만큼 회전시킨 게 곧 경계 방향이다. 하드코딩된 값을 따로 두지 않고
        // config.captureRadius를 그대로 참조해야, 그 값이 바뀌어도(예: 5.4cm로 재조정) 여기도
        // 같이 맞게 따라간다.
        let boundaryAngleOffset = atan(config.captureRadius / ballAxisDistance)
        let centerDirection = solution.direction

        // 시각화 경로는 새로 직선을 그리지 않고, 이미 구해둔 중앙 해의 실제(지형 따라 휘어진)
        // 경로를 공 위치를 중심으로 그만큼 통째로 회전시켜서 만든다 — 직선으로 새로 그리면
        // 지형 곡률을 못 따라가서 홀 근처에 안 닿고 계속 벗어나 버리는데, 중앙 경로를 그대로
        // 회전시키면 같은 곡률을 유지한 채 끝점도 홀 근처(회전 각도만큼만 벗어난 지점)에
        // 자연스럽게 떨어진다. 높이(Y)도 중앙 경로가 이미 갖고 있던 값 그대로 회전되므로
        // 추가로 지형을 조회할 필요가 없다.
        func rotatedPath(by angle: Float) -> [simd_float3] {
            solution.path.map { point in
                let relative = point - ballPosition
                return ballPosition + rotateHorizontal(relative, by: angle)
            }
        }

        // a=왼쪽(더 작은/음수 쪽), b=오른쪽(더 큰/양수 쪽)으로 고정한다 — directionRange와
        // 같은 규칙.
        solution.directionBoundaryA = simd_normalize(rotateHorizontal(centerDirection, by: -boundaryAngleOffset))
        solution.boundaryAPath = rotatedPath(by: -boundaryAngleOffset)

        solution.directionBoundaryB = simd_normalize(rotateHorizontal(centerDirection, by: boundaryAngleOffset))
        solution.boundaryBPath = rotatedPath(by: boundaryAngleOffset)

        return solution
    }

    /// solution의 속도는 고정한 채 방향(좌우 각도)만 조금씩 틀어가며, 여전히 캡처
    /// 반경 이내로 들어오는 각도의 두 경계를 찾는다. 먼저 coarseAngleStep 간격으로
    /// 훑어서 "들어가다가 안 들어가기 시작하는" 구간을 대략 찾고, 그 구간 안에서
    /// 이분탐색으로 정밀하게 좁힌다 — 다잉 퍼팅처럼 여유가 1도도 안 되는 좁은 범위도
    /// coarse 스텝 하나 만에 "범위 없음"으로 뭉개지 않고 정확히 잡아낸다.
    func directionRange(
        for solution: PuttSolution,
        ballPosition: simd_float3,
        holePosition: simd_float3,
        coarseAngleStep: Float = (Float.pi / 180) * 1.0,
        maxCoarseSteps: Int = 60,
        bisectionIterations: Int = 8
    ) -> (a: simd_float3, b: simd_float3)? {
        func captures(_ direction: simd_float3) -> Bool {
            let test = PuttSolution(direction: direction, speed: solution.speed)
            guard let result = simulateForward(test, from: ballPosition, holePosition: holePosition) else { return false }
            return result.closestDistance <= config.captureRadius
        }

        guard captures(solution.direction) else { return nil }

        func findBoundary(sign: Float) -> simd_float3 {
            var lastGoodAngle: Float = 0
            var firstBadAngle: Float?
            for step in 1...maxCoarseSteps {
                let angle = sign * coarseAngleStep * Float(step)
                if captures(rotateHorizontal(solution.direction, by: angle)) {
                    lastGoodAngle = angle
                } else {
                    firstBadAngle = angle
                    break
                }
            }
            guard var badAngle = firstBadAngle else {
                return rotateHorizontal(solution.direction, by: sign * coarseAngleStep * Float(maxCoarseSteps))
            }
            var goodAngle = lastGoodAngle
            for _ in 0..<bisectionIterations {
                let midAngle = (goodAngle + badAngle) / 2
                if captures(rotateHorizontal(solution.direction, by: midAngle)) {
                    goodAngle = midAngle
                } else {
                    badAngle = midAngle
                }
            }
            return rotateHorizontal(solution.direction, by: goodAngle)
        }

        // a=왼쪽, b=오른쪽으로 고정한다 — sign: -1(왼쪽으로 회전)이 a, sign: 1(오른쪽으로
        // 회전)이 b.
        return (findBoundary(sign: -1), findBoundary(sign: 1))
    }

    private struct ForwardSimulationResult {
        let closestPosition: simd_float3
        let closestDistance: Float
        let path: [simd_float3]
    }

    private func simulateForward(_ candidate: PuttSolution, from ballPosition: simd_float3, holePosition: simd_float3) -> ForwardSimulationResult? {
        let ball = GolfBall(initialPosition: ballPosition, initialVelocity: candidate.direction * candidate.speed)
        ball.rollingResistance = config.rollingResistance

        var closestPosition = ballPosition
        var closestDistance = horizontalDistance(ballPosition, holePosition)
        var path: [simd_float3] = [ballPosition]
        var previousPosition = ballPosition

        for step in 0..<config.maxForwardSteps {
            guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
            ball.updateForwardWithSlip(deltaTime: config.deltaTime, surfaceNormal: normal)

            // 스텝 끝점만 보지 않고, 직전~다음 위치를 잇는 선분 전체에서 홀컵까지의 최소
            // 거리를 본다 — 안 그러면 빠른 공이 좁은 홀컵 반경(3.3cm)을 두 샘플 사이에서
            // 그냥 지나쳐버려도 "홀인했는데 못 잡는" 경우가 생긴다.
            let (closestOnSegment, distance) = closestHorizontalPoint(from: previousPosition, to: ball.position, target: holePosition)
            if distance < closestDistance {
                closestDistance = distance
                closestPosition = closestOnSegment
            }

            if distance <= config.captureRadius {
                path.append(closestOnSegment)
                break
            }

            previousPosition = ball.position
            if step % 5 == 0 {
                path.append(ball.position)
            }
            if ball.hasStopped {
                path.append(ball.position)
                break
            }
        }

        return ForwardSimulationResult(closestPosition: closestPosition, closestDistance: closestDistance, path: path)
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

    /// 선분(a→b) 위에서 target에 가장 가까운 점과 그 수평(X,Z) 거리를 반환한다 —
    /// 매 스텝 끝점만 확인하면 그 사이(선분 중간)에서 목표를 스쳐 지나가는 경우를
    /// 놓칠 수 있어, forward 캡처 판정과 백워드 도달 판정 둘 다 이 방식을 쓴다.
    private func closestHorizontalPoint(from a: simd_float3, to b: simd_float3, target: simd_float3) -> (point: simd_float3, distance: Float) {
        let abHorizontal = simd_float2(b.x - a.x, b.z - a.z)
        let lengthSquared = simd_dot(abHorizontal, abHorizontal)
        let t: Float
        if lengthSquared > 0.0001 {
            let atHorizontal = simd_float2(target.x - a.x, target.z - a.z)
            t = max(0, min(1, simd_dot(atHorizontal, abHorizontal) / lengthSquared))
        } else {
            t = 0
        }
        let closest = a + (b - a) * t
        return (closest, horizontalDistance(closest, target))
    }
}

//
//  PuttRangeFinder.swift
//  EasyPutt
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
    /// 각도 범위의 두 경계 방향벡터. findSolutions()에서 directionRange(...)로
    /// 채워지며, 어느 쪽이 "왼쪽"/"오른쪽"인지는 puttRelative()로 판단해야 한다
    /// (여기선 그냥 두 경계일 뿐, 순서가 좌/우를 의미하지 않는다).
    var directionBoundaryA: simd_float3?
    var directionBoundaryB: simd_float3?
    /// directionBoundaryA/B 방향으로 쳤을 때의 정방향 시뮬레이션 경로 — 시각화에서
    /// "이 두 경계 사이로 치면 들어간다"는 걸 보여주기 위함. path와 같은 다운샘플링 규칙.
    var boundaryAPath: [simd_float3] = []
    var boundaryBPath: [simd_float3] = []
}

struct PuttRangeFinderConfig {
    var rollingResistance: Float = 0.35
    var deltaTime: Float = 0.05
    var maxBackwardSteps: Int = 4000
    var maxForwardSteps: Int = 4000
    /// 홀인으로 판정하는 최대 허용 오차 — 홀컵 반경(≈5.4cm) - 공 반지름(2.135cm).
    var captureRadius: Float = 0.033
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
        }
        return solutions
    }

    /// forward 시뮬레이션(verify/correct)을 전혀 쓰지 않고, 백워드 추적 + 이분탐색만으로
    /// 해와 좌우 범위를 직접 구한다. holeCrossingSpeeds 각각에 대해 backwardOnlySolve를
    /// 호출한다 — findSolutions()와 대응되는 "백워드 전용" 버전.
    func findSolutionsBackwardOnly(ballPosition: simd_float3, holePosition: simd_float3) -> [PuttSolution] {
        var solutions: [PuttSolution] = []
        for crossingSpeed in config.holeCrossingSpeeds {
            guard let solution = backwardOnlySolve(
                ballPosition: ballPosition,
                holePosition: holePosition,
                crossingSpeed: crossingSpeed
            ) else { continue }
            solutions.append(solution)
        }
        return solutions
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
        crossingSpeed: Float,
        coarseAngleStep: Float = (Float.pi / 180) * 1.0,
        maxCoarseSteps: Int = 89,
        bisectionIterations: Int = 24
    ) -> PuttSolution? {
        guard crossingSpeed > 0 else { return nil }

        let toBall = ballPosition - holePosition
        let toBallHorizontal = simd_float3(toBall.x, 0, toBall.z)
        let ballAxisDistance = simd_length(toBallHorizontal)
        guard ballAxisDistance > 0.0001 else { return nil }
        let toBallUnit = toBallHorizontal / ballAxisDistance
        let forwardAxis = -toBallUnit
        let rightAxis = simd_float3(-forwardAxis.z, 0, forwardAxis.x)

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

            for step in 0..<config.maxBackwardSteps {
                guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
                ball.updateFromTorque(deltaTime: -config.deltaTime, surfaceNormal: normal)

                let progress = simd_dot(
                    simd_float3(ball.position.x - holePosition.x, 0, ball.position.z - holePosition.z),
                    toBallUnit
                )
                if progress >= ballAxisDistance {
                    path.append(ball.position)
                    return BackwardTrace(angle: angle, crossingPosition: ball.position, velocity: ball.velocity, path: path)
                }
                if step % 5 == 0 {
                    path.append(ball.position)
                }
                if simd_length(ball.velocity) < 0.0001 { return nil }
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
            guard let (baseOffset, baseTrace) = offset(at: startAngle, target: target) else {
                print("[백워드전용] target=\(target): \(startAngle * 180 / .pi)도(시작점) 추적 실패")
                return nil
            }
            // 수렴 허용치를 2.5cm로 느슨하게 잡는다 — 어차피 captureRadius(3.3cm) 자체가
            // 보수적인 근사치라, 굳이 mm 단위까지 이분탐색을 더 돌릴 필요가 없다.
            if abs(baseOffset) < 0.025 { return baseTrace }

            // 속도 벡터를 +각도로 돌리면 rightAxis 쪽으로 기울지만, dt<0(역방향 적분)라
            // 실제 위치 이동은 속도의 반대 방향이라 결과 경로는 -rightAxis(반대쪽)로 휜다.
            // 그래서 baseOffset이 +(공 기준 오른쪽으로 빗나감)이면 그걸 줄이기 위해
            // +각도 쪽으로 걸어가야 한다(그 반대가 아니라).
            let searchSign: Float = baseOffset > 0 ? 1 : -1
            var lowAngle: Float = startAngle
            var highAngle: Float?
            let lowIsPositive = baseOffset > 0

            for step in 1...maxCoarseSteps {
                let angle = startAngle + searchSign * coarseAngleStep * Float(step)
                guard let (value, _) = offset(at: angle, target: target) else {
                    print("[백워드전용] target=\(target): \(angle * 180 / .pi)도에서 추적 끊김, 그 전까지만 탐색")
                    break
                }
                if (value > 0) != lowIsPositive {
                    highAngle = angle
                    break
                }
                lowAngle = angle
            }

            guard var high = highAngle else {
                print("[백워드전용] target=\(target): \(startAngle * 180 / .pi)도에서 \(maxCoarseSteps)도 안에 부호 반전 못 찾음(브라켓 실패)")
                return nil
            }
            var low = lowAngle
            var bestTrace: BackwardTrace?

            for _ in 0..<bisectionIterations {
                let mid = (low + high) / 2
                guard let (value, trace) = offset(at: mid, target: target) else { return bestTrace }
                bestTrace = trace
                if (value > 0) == lowIsPositive {
                    low = mid
                } else {
                    high = mid
                }
            }
            return bestTrace
        }

        guard let center = solveAngle(target: 0) else { return nil }
        let speed = simd_length(center.velocity)
        guard speed > 0.0001 else { return nil }

        var solution = PuttSolution(
            direction: center.velocity / speed,
            speed: speed,
            path: center.path.reversed()
        )

        // 경계는 추가 시뮬레이션 없이 순수 기하로 구한다 — 3cm만큼 옆으로 비켜나는 데 필요한
        // 각도를 작은각 근사(atan(3cm/거리))로 구해서, 중앙 해의 최종 방향벡터를 그만큼
        // 회전시킨 게 곧 경계 방향이다(중앙해 자체도 2.5cm 허용치로 느슨하게 구했으니, 굳이
        // captureRadius(3.3cm) 정밀값을 쓸 필요 없이 3cm로 반올림해도 오차는 무시할 만하다).
        // 백워드 추적을 또 돌리는 것보다 훨씬 빠르고, 시각화 경로도 실제 궤적 대신 공→그
        // 방향으로 뻗은 직선으로 대체한다(공→홀 거리만큼).
        let boundaryShiftDistance: Float = 0.03
        let boundaryAngleOffset = atan(boundaryShiftDistance / ballAxisDistance)
        let centerDirection = solution.direction

        let boundaryADirection = simd_normalize(rotateHorizontal(centerDirection, by: boundaryAngleOffset))
        solution.directionBoundaryA = boundaryADirection
        solution.boundaryAPath = [ballPosition, ballPosition + boundaryADirection * ballAxisDistance]

        let boundaryBDirection = simd_normalize(rotateHorizontal(centerDirection, by: -boundaryAngleOffset))
        solution.directionBoundaryB = boundaryBDirection
        solution.boundaryBPath = [ballPosition, ballPosition + boundaryBDirection * ballAxisDistance]

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

        return (findBoundary(sign: 1), findBoundary(sign: -1))
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

        for step in 0..<config.maxForwardSteps {
            guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }
            ball.updateFromTorque(deltaTime: config.deltaTime, surfaceNormal: normal)

            let distance = horizontalDistance(ball.position, holePosition)
            if distance < closestDistance {
                closestDistance = distance
                closestPosition = ball.position
            }

            // 홀 반경 안에 들어온 순간 그 지점에서 즉시 끊는다 — 매 스텝(5스텝마다가
            // 아니라)마다 확인해야 한다, 안 그러면 빠른 공이 좁은 홀컵 반경(3.3cm)을
            // 두 샘플 사이에 그냥 지나쳐서 "홀인했는데 못 자르는" 경우가 생긴다.
            if distance <= config.captureRadius {
                path.append(ball.position)
                break
            }

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
}

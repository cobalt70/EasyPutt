# 미끄럼→구름 전환 물리 개선 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `PuttRangeFinder.simulateForward()`가 쓰는 정방향 시뮬레이션에, 미끄럼 구간(임팩트 직후 순수구름 전이 전)에서 마찰력이 병진(위치/속도)에도 반영되고 경사가속도가 5/7로 과소평가되지 않는 새 물리를 추가한다.

**Architecture:** `GolfBall`에 정방향 전용 신규 메서드 `updateForwardWithSlip`을 추가한다(기존 `updateFromTorque`는 역방향 대칭성이 필요한 백워드 추적이 계속 쓰므로 변경 없음). 접촉점 상대속도(`v_contact = velocity + angularVelocity × r`)를 미끄럼 판정과 마찰 방향 계산에 공용으로 쓴다. `PuttRangeFinder.simulateForward()`의 물리 호출 한 줄만 새 메서드로 교체한다.

**Tech Stack:** Swift, simd, XCTest.

## Global Constraints

- 설계 문서: `docs/superpowers/specs/2026-07-19-slip-roll-physics-design.md` (모든 태스크가 이 문서의 결정사항을 따른다).
- `GolfBall.updateFromTorque`(역방향 대칭성 필요, 백워드 추적이 사용)와 `PuttRangeFinder.backwardCandidate`/`traceBackward`는 변경하지 않는다.
- `verify()`/`correct()`의 보정 알고리즘(`directionGain`/`speedGain`/`maxCorrectionIterations`)은 변경하지 않는다.
- `muKinetic`(현재 `GolfBall.swift`에 `0.2`로 하드코딩)은 그대로 유지한다 — 실측 데이터 기반 보정은 이번 범위 밖.
- 커밋은 태스크 단위로 한다.
- 알려진 환경 제약: `xcodebuild test`는 이 프로젝트에서 `INFOPLIST_KEY_UIRequiredDeviceCapabilities=arkit` 때문에 시뮬레이터에서 테스트 호스트 앱이 launch되지 않아 실행할 수 없다. 실기기 destination(`-destination "id=<DEVICE_ID>"`)이 필요하다. 실기기를 이 환경에서 못 찾으면(`xcrun xctrace list devices`로 확인), Step에 안내된 대로 순수 로직만 별도 standalone Swift 스크립트로 검증하고, 정식 XCTest 코드는 그대로 커밋해서 나중에 실기기에서 확인할 수 있게 한다.

---

### Task 1: `GolfBall.updateForwardWithSlip` 신규 물리 함수

**Files:**
- Modify: `EasyPutt/GolfBall.swift`
- Test: `EasyPuttTests/GolfBallRollingResistanceTests.swift`

**Interfaces:**
- Produces: `func updateForwardWithSlip(deltaTime dt: Float, surfaceNormal n: simd_float3)` — `GolfBall`의 internal(기본 접근수준) 메서드. Task 2가 `PuttRangeFinder.simulateForward()`에서 이 메서드를 호출한다.

- [ ] **Step 1: 실패하는 테스트 4개 작성**

`EasyPuttTests/GolfBallRollingResistanceTests.swift` 맨 끝(`}` 앞)에 추가:

```swift

    // MARK: - updateForwardWithSlip (미끄럼→구름 전환, 병진에도 마찰 반영)

    func testSlipPhaseAppliesFullSlopeAccelerationNotReducedByRollingFactor() {
        // 속도를 경사 방향(x)과 수직인 z축으로 둬서, 마찰이 x축 가속에 영향을 주지
        // 않게 분리한다 — x축 가속 변화는 순수하게 "경사가속도가 5/7로 줄었는지
        // 아닌지"만 반영한다.
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(0, 0, 1.0))
        ball.rollingResistance = 0.35
        let tiltedNormal = simd_normalize(simd_float3(0.1, 1, 0))
        let dt: Float = 0.1

        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: tiltedNormal)

        let gravity: Float = 9.8
        let tiltAngle = atan(Float(0.1))
        let fullSlopeAccelX = gravity * sin(tiltAngle) * cos(tiltAngle)
        let reducedSlopeAccelX = fullSlopeAccelX * (5.0 / 7.0)

        XCTAssertGreaterThan(ball.velocity.x, reducedSlopeAccelX * dt,
            "미끄럼 구간의 경사가속도는 5/7 공식보다 커야 한다")
        XCTAssertEqual(ball.velocity.x, fullSlopeAccelX * dt, accuracy: 0.01,
            "미끄럼 구간에서는 경사가속도(gravityParallel)가 5/7로 줄지 않고 그대로 실려야 한다")
    }

    func testTransitionsFromSlipDecelerationToRollingDeceleration() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(2.0, 0, 0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.01

        let speedBeforeFirstStep = simd_length(ball.velocity)
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        let firstStepDrop = speedBeforeFirstStep - simd_length(ball.velocity)

        // 초반엔 미끄럼 상태라 muKinetic(0.2) 기준으로 감속해야 한다(0.2×9.8×dt≈0.0196) —
        // rollingResistance(0.35×dt=0.0035)보다 훨씬 크다.
        XCTAssertEqual(firstStepDrop, 0.2 * 9.8 * dt, accuracy: 0.002,
            "미끄럼 첫 스텝은 muKinetic 기준으로 감속해야 한다")

        for _ in 0..<200 {
            ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        }

        let speedBeforeLateStep = simd_length(ball.velocity)
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        let lateStepDrop = speedBeforeLateStep - simd_length(ball.velocity)

        // 충분히 지나면 순수구름으로 전환되어 rollingResistance 기준으로 감속해야 한다.
        XCTAssertEqual(lateStepDrop, ball.rollingResistance * dt, accuracy: 0.002,
            "충분한 스텝 이후에는 rollingResistance 기준(순수구름)으로 감속해야 한다")
    }

    func testRollingPhaseUsesReducedSlopeAcceleration() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(2.0, 0, 0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.01

        // 평지에서 충분히 스텝을 돌려 순수구름 상태로 전환시킨다(평지는 경사가
        // 없어서 전환 여부만 깨끗하게 만들 수 있다).
        for _ in 0..<200 {
            ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        }

        // 이제 경사면으로 바꿔서 한 스텝 — 이미 순수구름 상태이므로 5/7 공식이
        // 적용되어야 한다(testSlipPhase...와 반대 검증).
        let tiltedNormal = simd_normalize(simd_float3(0.1, 1, 0))
        let velocityXBefore = ball.velocity.x
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: tiltedNormal)

        let gravity: Float = 9.8
        let tiltAngle = atan(Float(0.1))
        let reducedSlopeAccelX = gravity * sin(tiltAngle) * cos(tiltAngle) * (5.0 / 7.0)
        let velocityChangeX = ball.velocity.x - velocityXBefore

        XCTAssertEqual(velocityChangeX, reducedSlopeAccelX * dt, accuracy: 0.01,
            "이미 순수구름 상태면 5/7 공식이 적용되어야 한다")
    }

    func testFlatGroundHasNoLateralDeflectionDuringSlip() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(0, 0, 1.0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)

        ball.updateForwardWithSlip(deltaTime: 0.05, surfaceNormal: flatNormal)

        XCTAssertEqual(ball.velocity.x, 0, accuracy: 0.0001,
            "평지에서는 미끄럼 구간에도 경사에 의한 옆방향 힘이 없어야 한다")
        XCTAssertLessThan(ball.velocity.z, 1.0,
            "진행 방향으로는 마찰에 의해 감속되어야 한다")
    }
```

- [ ] **Step 2: 테스트가 컴파일 실패하는지 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD FAILED — `updateForwardWithSlip`가 아직 없어서 컴파일 에러(`GolfBallRollingResistanceTests.swift`에서 "value of type 'GolfBall' has no member 'updateForwardWithSlip'" 계열 에러).

- [ ] **Step 3: `updateForwardWithSlip` 구현**

`EasyPutt/GolfBall.swift`의 `updateFromTorque` 메서드(50~112줄) 바로 다음, `applyRollingResistance` 메서드 앞에 추가:

```swift
    /// 미끄럼 상태 판정 임계값(m/s) — 접촉점 상대속도 크기가 이보다 작으면
    /// 순수구름으로 본다.
    private static let slipThreshold: Float = 0.03

    /// 정방향(dt≥0) 전용 — 미끄럼 구간에서 마찰력이 병진(위치/속도)과 회전(토크)
    /// 모두에 반영되도록 접촉점 상대속도 기준으로 계산한다. updateFromTorque는
    /// 역방향 대칭성이 필요한 백워드 추적이 계속 쓰므로 그대로 두고, 이 함수는
    /// PuttRangeFinder.simulateForward() 전용이다.
    func updateForwardWithSlip(deltaTime dt: Float, surfaceNormal n: simd_float3) {
        let gravityParallel = gravity - simd_dot(gravity, n) * n

        // 접촉점(중심에서 -radius*n 방향)의 지면 대비 상대속도.
        let r = -radius * n
        let vContact = velocity + simd_cross(angularVelocity, r)
        let slipSpeed = simd_length(vContact)

        let acceleration: simd_float3
        let rotationAxis: simd_float3
        let isSliding = slipSpeed > Self.slipThreshold

        if isSliding {
            // 미끄럼 구간: 접촉점 상대속도 기준 마찰력이 병진과 회전에 동시에 작용한다.
            // 5/7 계수(순수구름 구속조건 전제)는 아직 적용하지 않는다.
            let normalAccel = -simd_dot(gravity, n)
            let frictionAccMag = muKinetic * normalAccel
            let frictionDir = -vContact / slipSpeed
            let frictionAcc = frictionDir * frictionAccMag

            acceleration = gravityParallel + frictionAcc

            let crossVec = simd_cross(n, frictionDir)
            rotationAxis = simd_length(crossVec) > 0.0001 ? simd_normalize(crossVec) : simd_float3(0, 1, 0)
            let torqueMag = radius * frictionAccMag
            let inertia = (2.0 / 5.0) * mass * pow(radius, 2)
            let angularAccel = torqueMag / inertia
            angularVelocity += rotationAxis * angularAccel * dt
        } else {
            // 순수구름 구간: 기존 updateFromTorque와 동일한 물리.
            let accelMag = simd_length(gravityParallel) * (5.0 / 7.0)
            acceleration = accelMag > 0.0001 ? simd_normalize(gravityParallel) * accelMag : .zero
            rotationAxis = simd_length(velocity) > 0.0001 ? simd_normalize(simd_cross(n, simd_normalize(velocity))) : simd_float3(0, 1, 0)
        }

        let entryVelocity = velocity
        position += entryVelocity * dt + 0.5 * acceleration * dt * dt
        velocity += acceleration * dt

        if isSliding {
            // 마찰이 이미 위에서 acceleration에 반영됐으므로 applyRollingResistance는
            // 호출하지 않는다(구름저항은 순수구름 상태에서만 성립하는 별개 메커니즘).
        } else {
            applyRollingResistance(deltaTime: dt)
            guard simd_length(velocity) > 0.0001 else { return }
            let targetAngular = simd_length(velocity) / radius
            angularVelocity = rotationAxis * targetAngular
        }

        let angle = simd_length(angularVelocity) * dt
        if angle.isFinite && simd_length(rotationAxis) > 0.0001 {
            let deltaRotation = simd_quatf(angle: angle, axis: rotationAxis)
            rotation = simd_normalize(deltaRotation * rotation)
        }
    }
```

- [ ] **Step 4: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 테스트 실행 — 실기기 우선, 없으면 standalone 검증**

먼저 연결된 실기기가 있는지 확인한다:

Run: `xcrun xctrace list devices 2>&1 | grep -v Simulator`

기기가 있으면:

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "id=<DEVICE_ID>" test -only-testing:EasyPuttTests/GolfBallRollingResistanceTests`
Expected: PASS (기존 4개 + 신규 4개, 총 8개)

기기가 없으면(이 실행 환경에서 흔한 케이스), `GolfBall.updateForwardWithSlip`의 로직만 떼어서 standalone Swift로 빠르게 검증한다 — XCTest 코드 자체는 그대로 커밋해두고, 실기기가 생기면 그때 정식으로 돌린다:

```bash
cat > /tmp/verify_slip.swift << 'EOF'
import simd

func gravityParallelOf(_ n: simd_float3) -> simd_float3 {
    let gravity = simd_float3(0, -9.8, 0)
    return gravity - simd_dot(gravity, n) * n
}

// Test 1 재현: 경사 x, 속도 z 방향일 때 x축 가속이 5/7이 아니라 full이어야 함
let n1 = simd_normalize(simd_float3(0.1, 1, 0))
let gp1 = gravityParallelOf(n1)
let muKinetic: Float = 0.2
let normalAccel1 = -simd_dot(simd_float3(0, -9.8, 0), n1)
let velocity1 = simd_float3(0, 0, 1.0)
let vContact1 = velocity1  // angularVelocity == 0
let frictionDir1 = -vContact1 / simd_length(vContact1)
let frictionAcc1 = frictionDir1 * (muKinetic * normalAccel1)
let accel1 = gp1 + frictionAcc1
let dt: Float = 0.1
let velocityAfter1 = velocity1 + accel1 * dt
print("velocity1.x after 1 step:", velocityAfter1.x, "(expect ≈ gravityParallel.x × dt =", gp1.x * dt, ")")
EOF
swift /tmp/verify_slip.swift
```

Expected: 출력된 `velocity1.x`가 `gravityParallel.x × dt` 값과 비슷하게 나오는지(둘 다 콘솔에 찍힘, 육안 비교) — GolfBall 클래스 자체를 컴파일하는 게 아니라 같은 수식만 재현해서 방향성이 맞는지 빠르게 확인하는 용도다. 정확한 검증은 실기기에서 XCTest로 한다.

- [ ] **Step 6: 커밋**

```bash
git add EasyPutt/GolfBall.swift EasyPuttTests/GolfBallRollingResistanceTests.swift
git commit -m "미끄럼 구간에서 마찰이 병진에도 반영되는 updateForwardWithSlip 추가"
```

---

### Task 2: `PuttRangeFinder`에 연결

**Files:**
- Modify: `EasyPutt/RangeFinder/PuttRangeFinder.swift:539`

**Interfaces:**
- Consumes: `GolfBall.updateForwardWithSlip(deltaTime:surfaceNormal:)` (Task 1에서 추가)

- [ ] **Step 1: `simulateForward()`의 물리 호출 교체**

`EasyPutt/RangeFinder/PuttRangeFinder.swift:539`의 현재 코드:

```swift
            ball.updateFromTorque(deltaTime: config.deltaTime, surfaceNormal: normal)
```

`simulateForward(_:from:holePosition:)` 메서드(528줄에서 시작) 안에 있는 이 줄을 찾아서(주변 문맥: `guard let normal = terrain.nearestNormal(to: ball.position) else { return nil }` 바로 다음 줄) 다음으로 바꾼다:

```swift
            ball.updateForwardWithSlip(deltaTime: config.deltaTime, surfaceNormal: normal)
```

`backwardCandidate`(111줄)와 `traceBackward`(233줄) 안의 `ball.updateFromTorque(deltaTime: -config.deltaTime, ...)` 두 줄은 건드리지 않는다 — 역방향 추적은 그대로 기존 물리를 쓴다.

- [ ] **Step 2: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 회귀 테스트 — 기존 PuttRangeFinder 테스트가 여전히 통과하는지 확인**

Task 1의 Step 5와 같은 방식으로 실기기 유무를 먼저 확인한다.

실기기가 있으면:

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "id=<DEVICE_ID>" test -only-testing:EasyPuttTests/PuttRangeFinderEndToEndTests -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests -only-testing:EasyPuttTests/PuttRangeFinderBackwardTests -only-testing:EasyPuttTests/GolfBallRollingResistanceTests`
Expected: PASS — 특히 `testFindSolutionsReturnsAtLeastOneVerifiedSolution`(완만한 내리막 지형에서 해가 나오는지)과 `testBackwardIntegrationRoundTripsOnSteepSlope`(역방향 왕복, `updateFromTorque` 안 건드렸으므로 변경 없이 통과해야 함)가 통과하는지 확인.

실기기가 없으면: 이 회귀 테스트는 물리 공식이 아니라 솔버 전체 파이프라인(백워드 추적 + forward 보정 반복)이 여전히 수렴하는지를 확인하는 것이라 standalone 스크립트로 재현하기 어렵다 — 컴파일 성공(Step 2)까지만 확인하고, 테스트 코드는 그대로 둔 채 실기기 확인이 필요하다는 걸 보고서에 명시한다.

- [ ] **Step 4: 커밋**

```bash
git add EasyPutt/RangeFinder/PuttRangeFinder.swift
git commit -m "simulateForward가 미끄럼 반영 물리(updateForwardWithSlip)를 쓰도록 연결"
```

---

## 계획 자체 검토(Self-Review) 결과

- **스펙 커버리지**: 설계 문서 2절(새 물리 함수)→Task 1, 3절(PuttRangeFinder 연결)→Task 2, 4절(테스트 전략의 신규 테스트 4개)→Task 1 Step 1, 4절의 회귀 테스트 항목→Task 2 Step 3. 5절(PuttPro 비교)은 설계 근거 문서이지 구현 대상이 아니므로 태스크 없음(의도된 것).
- **타입/시그니처 일관성**: `updateForwardWithSlip(deltaTime:surfaceNormal:)` 시그니처가 Task 1(정의)과 Task 2(호출)에서 동일. `GolfBall.rollingResistance`(기존 internal var), `GolfBall.velocity`(기존 internal var) 등 테스트가 쓰는 기존 API도 실제 파일과 일치 확인함(직접 재확인).
- **플레이스홀더 스캔**: Task 1 Step 3 초안에 Swift 코드가 아닌 한글 설명이 섞여 들어간 줄이 있어서, 빈 `if` 분기 + 주석으로 바로 고쳤다(아래 최종 코드 블록에 반영됨, 별도 블록 없이 하나로 정리).

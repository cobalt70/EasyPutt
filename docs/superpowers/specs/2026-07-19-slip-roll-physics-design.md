# 퍼트 물리 모델: 미끄럼→구름 전환 개선 설계 문서

**Goal:** `PuttRangeFinder.simulateForward()`(B+F의 `verify()`/`correct()` 보정 루프와 B의 최종 1회 검증이 공유하는 정방향 시뮬레이션)의 물리를, 임팩트 직후 미끄러지는 구간에서 마찰력이 병진(위치/속도)에도 반영되고 경사에 의한 커브가 과소평가되지 않도록 개선한다.

**Non-goals:**
- 백워드 추적(`GolfBall.updateFromTorque`, `PuttRangeFinder.backwardCandidate`/`traceBackward`)은 건드리지 않는다 — 어차피 "근사 후보"이고 forward로 다시 검증되므로, 역방향 대칭성이 필요한 이 함수는 그대로 두고 정방향 전용 새 함수를 별도로 만든다.
- `verify()`/`correct()`의 보정 알고리즘 자체(`directionGain`/`speedGain`/`maxCorrectionIterations`)는 바꾸지 않는다.
- PuttPro처럼 백워드 추적 없이 전수탐색(brute-force forward sweep)만으로 가는 아키텍처 전환은 하지 않는다 — PuttPro 코드는 아이디어 참고용으로만 썼다.
- `muKinetic`(현재 `GolfBall.swift`에 `0.2`로 하드코딩)을 실측 통계 기반으로 정밀 보정하는 작업은 범위 밖이다 — 같은 세션에서 이미 별도로 결론 내림: 신뢰할 실측 데이터가 없고, 이 값 자체가 궤적 자체보다는 마찰력의 크기(병진+회전 모두에 이제 영향)를 결정하는 값이라 정확도가 아쉬우면 실기기에서 관찰하며 튜닝하는 쪽을 택함. 이번 설계는 하드코딩된 `0.2`를 그대로 사용한다.

## 1. 배경

`GolfBall.updateFromTorque`(정방향·역방향 공유, `dt` 부호로 분기)는 병진 가속도로 `gravityParallel × (5/7)`을 **무조건** 적용한다. 이 5/7 계수는 "공이 이미 미끄러짐 없이 순수하게 구르고 있다"는 구속조건(no-slip) 하에서만 성립하는 고전역학 결과다 — 균일한 구가 경사를 굴러 내려갈 때 위치에너지의 2/7이 회전운동에너지로 가기 때문에 나오는 값이다.

`muKinetic` 기반 마찰력(`frictionForce = muKinetic × normalForce`)은 토크 계산에만 쓰여서 `angularVelocity`/`rotation`(회전)만 갱신하고, `position`/`velocity`(병진)에는 전혀 피드백되지 않는다 — 코드를 직접 추적해서 확인했다(`updateFromTorque` 안에서 병진 갱신은 토크 블록보다 먼저, 완전히 분리된 코드로 끝난다).

실제로는 미끄러지는 동안(아직 순수구름 구속조건이 안 걸린 상태) 마찰력 하나가:
1. 토크를 만들어 각속도(회전)를 바꾸고
2. 그 반작용으로 병진속도(위치/방향)도 동시에 바꿔야 하며
3. 이 구간의 경사 가속도는 5/7이 아니라 (구속조건이 없으므로) 더 크게 실려야 한다

이 단순화는 README의 "알려진 미구현/제한 사항"에 이미 "슬라이딩 마찰 → 구름 전환 구간의 병진 감속(토크로 인한 병진 속도 손실)은 단순화되어 있습니다"로 문서화되어 있다.

## 2. 새 물리 함수: `GolfBall.updateForwardWithSlip(deltaTime:surfaceNormal:)`

정방향(`dt ≥ 0`) 전용 신규 메서드. 기존 `updateFromTorque`는 백워드 추적이 역방향 대칭성을 위해 계속 사용하므로 변경하지 않는다.

### 2.1 미끄럼 판정 및 마찰 방향 — 접촉점 상대속도 기준

PuttPro와 EasyPutt의 기존 `updateFromTorque`는 둘 다 "실제 각속도 크기 vs 완전구름 각속도 크기"(`|angularVelocity|` vs `|velocity|/radius`)를 비교해서 전환을 판정한다. 이 방식은 크기만 비교하고 방향(회전축)은 안 보기 때문에, 이론상 각속도 방향이 어긋나도 크기만 맞으면 "구른다"고 오판할 여지가 있다.

새 함수는 대신 **접촉점의 실제 상대속도**를 직접 계산해서 그 크기가 충분히 작아졌는지로 판정한다:

```
r = -radius × n                                    // 중심 → 접촉점 벡터
v_contact = velocity + cross(angularVelocity, r)    // 접촉점의 지면 대비 상대속도
```

`|v_contact| > slipThreshold`(제안값 0.02~0.05 m/s, 정확한 값은 테스트로 튜닝)이면 미끄럼 상태, 아니면 순수구름 상태로 판정한다. 마찰 방향(`frictionDir`)도 이 벡터에서 바로 나오므로, 마찰력 계산에 필요한 값을 전환 판정에 그대로 재사용한다 — 추가 계산이 들지 않는다.

### 2.2 미끄럼 구간 (`|v_contact| > slipThreshold`)

```
normalAccel = -dot(gravity, n)
frictionAccMag = muKinetic × normalAccel
frictionDir = -normalize(v_contact)
frictionAcc = frictionDir × frictionAccMag

acceleration = gravityParallel + frictionAcc        // 5/7 없이 경사 전체 + 마찰, 병진에 반영
velocity += acceleration × dt
position += entryVelocity × dt + 0.5 × acceleration × dt²
```

토크는 같은 `frictionAcc`(또는 `frictionAccMag`)에서 유도한다 — 회전축은 기존 `updateFromTorque`와 같은 방식(`cross(n, frictionDir)` 계열), 관성모멘트는 `(2/5) × mass × radius²` 그대로 재사용.

### 2.3 구름 구간 (`|v_contact| ≤ slipThreshold`)

기존 `updateFromTorque`의 순수구름 처리와 동일하다:
```
acceleration = gravityParallel × (5/7)
velocity += acceleration × dt
applyRollingResistance(deltaTime: dt)               // rollingResistance(=muRolling) 감속
angularVelocity = rotationAxis × (|velocity| / radius)   // 각속도를 병진속도에 lock
```

전환 순간 가속도 공식이 (5/7 vs 풀 경사가속도로) 불연속적으로 바뀌는 것은 허용한다 — 실제로도 그 순간 지배적인 마찰 메커니즘 자체가 바뀌는 현상이라 물리적으로 부자연스럽지 않다.

## 3. PuttRangeFinder 연결

`PuttRangeFinder.simulateForward()` 안의 다음 한 줄만 교체한다:

```swift
// 변경 전
ball.updateFromTorque(deltaTime: config.deltaTime, surfaceNormal: normal)
// 변경 후
ball.updateForwardWithSlip(deltaTime: config.deltaTime, surfaceNormal: normal)
```

`simulateForward()`는 `verify()`(반복 보정 루프, B+F)와 `backwardOnlySolve()`의 최종 1회 forward 검증(B) 둘 다에서 호출되므로, 이 한 줄만 바꿔도 **두 솔버 모두 자동으로** 새 물리를 반영한다.

`backwardCandidate`/`traceBackward`(역방향 추적, `updateFromTorque` 사용)는 변경 없음 — 계속 근사 후보만 빠르게 찾고, `simulateForward()`(이제 새 물리 적용)가 그 후보를 실제로 검증/보정한다.

## 4. 테스트 전략

`EasyPuttTests/GolfBallRollingResistanceTests.swift`에 새 테스트를 추가한다(신규 함수 대상):

- **미끄럼 구간의 횡가속도 검증**: 경사면에서 1스텝 실행 후, 속도의 경사-수직 방향 성분 변화량이 5/7 공식이 예측하는 값보다 큰지(구체적 수치로).
- **접촉점 속도 수렴 검증**: 여러 스텝 반복 실행 시 `v_contact`(또는 이를 재현하는 테스트 헬퍼)의 크기가 점점 0에 가까워지는지 — 미끄럼→구름 전환이 실제로 일어남을 확인.
- **전환 이후 물리 동일성**: 전환된 이후에는 기존 `updateFromTorque`의 순수구름 결과(같은 초기 조건에서)와 동일하게 동작하는지.
- **평지에서는 커브 없음**: `gravityParallel = 0`인 평지에서는 미끄럼 구간에도 옆방향 가속이 없고 직진 감속만 있는지(회귀 방지 — 새 공식이 평지에서 이상한 옆방향 힘을 만들어내지 않는지).

기존 회귀 테스트(수정 없이 그대로 통과해야 함):
- `GolfBallRollingResistanceTests`의 기존 4개 테스트(특히 `testBackwardIntegrationRoundTripsOnSteepSlope` — `updateFromTorque`를 안 건드렸으므로 변경 없이 통과해야 함)
- `PuttRangeFinderEndToEndTests`/`VerifyTests`/`BackwardTests` — `simulateForward()`의 물리가 바뀐 뒤에도 기존 시나리오에서 여전히 해를 찾는지 재확인.

`xcodebuild test`는 이 세션에서 이미 확인된 환경 제약(`INFOPLIST_KEY_UIRequiredDeviceCapabilities=arkit` 때문에 시뮬레이터에서 테스트 호스트 앱이 launch 자체가 안 됨)이 있으므로, 실기기 destination(`-destination "id=<DEVICE_ID>"`)에서 실행해야 한다.

## 5. PuttPro와의 물리 공식 비교

같은 세션에서 PuttPro(`GolfBall.swift`/`FindPath.swift`) 코드를 직접 읽고 비교한 내용이다. "참고만 하고 그대로 가져오지 않는다"는 Non-goals를 뒷받침하는 근거로 남겨둔다.

| 물리량 | PuttPro | EasyPutt (기존 `updateFromTorque`) | EasyPutt (신규 `updateForwardWithSlip`) |
|---|---|---|---|
| 구름 구간 경사가속도 | `accelMag = \|gravityParallel\| × 5/7` — **미끄럼/구름 상태와 무관하게 항상 적용** | 항상 5/7 적용(구간 구분 없음) | **구름 구간에서만** 5/7 적용, 미끄럼 구간은 `gravityParallel` 전체 적용 |
| 미끄럼 구간 마찰 방향 | `frictionDir = -normalize(velocity)` — 병진속도 기준(각속도 영향 무시) | (병진에 미반영이라 해당 없음) | `frictionDir = -normalize(v_contact)` — 접촉점 상대속도 기준(각속도 반영) |
| 미끄럼 마찰의 병진 반영 | `velocity += frictionAcc × dt` — **반영됨** | **미반영**(토크만 갱신, 병진과 완전 분리) | **반영됨**(PuttPro처럼 병진에도 실림, 단 접촉점 기준으로 재계산) |
| 구름 구간 감속 | 같은 `frictionAcc`(muKinetic 기반)에 `reduceFactor=0.7`을 곱해서 재사용 — **muRolling과 무관한 임시 감쇠** | `rollingResistance`(=muRolling, stimp에서 직접 유도) — 마찰메커니즘 자체가 다름 | 기존과 동일하게 `rollingResistance` 사용(구름저항은 미끄럼마찰과 별개 메커니즘이라는 입장 유지) |
| 순수구름 전환 판정 | `\|angularVelocity\|` vs `\|velocity\|/radius` **크기 비교** | 동일(크기 비교, 임계값 `0.01`) | `\|v_contact\|`(접촉점 상대속도) **벡터 기반** — 마찰방향 계산에 쓰는 값을 그대로 재사용 |
| 회전축 | `cross(n, frictionDir)` 계열 | 동일 | 동일(단 `frictionDir`이 `v_contact` 기준으로 바뀜) |
| 관성모멘트(균일한 구) | `(2/5) × mass × radius²` | 동일 | 동일 |
| `muKinetic` 산출 | `muRolling × kineticRatio(stimp)` — stimp 구간별 경험적 배수(2.0~2.4) | 하드코딩 `0.2`, stimp와 무관 | 변경 없음(하드코딩 `0.2`) — 실측 통계 부재로 이번 설계 범위 밖(Non-goals) |
| 백워드(역방향) 적분 | **없음** — 전부 정방향 RK4 전수탐색(`adaptiveDirectionSearch`) | 있음(`dt<0`), `updateFromTorque`가 정/역방향 공유 | 해당 없음(정방향 전용 함수) — 백워드는 기존 `updateFromTorque` 그대로 사용 |

핵심 차이는 두 가지다: (1) PuttPro는 미끄럼-구름 전환에 정방향 전수탐색만 쓰므로 역방향 대칭성을 고려할 필요가 없었고, (2) 구름 구간 감속을 muRolling 없이 `reduceFactor` 임시값으로 근사했다 — 이번 설계는 EasyPutt에 이미 있는 정확한 `rollingResistance`를 구름 구간에 그대로 쓰고, 미끄럼 구간만 접촉점 속도 기준으로 새로 계산해서 두 메커니즘을 명확히 분리한다.

### PuttPro의 구름 구간 감속 방식이 갖는 문제

PuttPro의 구름 구간 감속을 풀어서 쓰면 `rollingPhaseAccel = muRolling × kineticRatio(stimp) × reduceFactor(0.7)`이다 — 즉 구름저항이라는 결과값 하나를 만드는 데, **muRolling(직접 유도된 실측 기반 값)을 kineticRatio라는 경험적 배수로 한 번 왜곡해서 muKinetic을 만들고, 거기에 다시 reduceFactor라는 또 다른 임의의 상수를 곱해서** 근사한다. 이건 두 가지로 물리적으로 앞뒤가 맞지 않는다:

1. **muRolling(구름저항)과 muKinetic(미끄럼마찰)은 애초에 서로 다른 메커니즘**이다(1절/앞선 대화에서 확인 — 구름저항은 잔디 변형손실 계열, 미끄럼마찰은 접촉점 상대속도가 있을 때만 발생하는 쿨롱 마찰). 구름 구간(이미 미끄러짐이 없는 상태)의 감속을 미끄럼마찰 값(muKinetic)에서 유도한다는 것 자체가, "미끄러짐이 없는 상태의 감속을 미끄러짐 마찰로 설명"하는 셈이라 개념이 뒤바뀌어 있다.
2. 설령 muKinetic을 어찌어찌 쓴다 쳐도, 그 muKinetic 자체가 이미 `muRolling × kineticRatio`로 muRolling에서 파생된 값인데, 거기에 `reduceFactor`라는 **세 번째 경험적 계수**를 또 곱한다 — 정작 필요한 건 muRolling 그 자체 하나뿐인데, muRolling → (kineticRatio 왜곡) → muKinetic → (reduceFactor 왜곡) → 구름감속, 이렇게 두 단계를 거쳐 원래 값에서 점점 멀어진 근사치를 쓰는 구조다.

EasyPutt의 신규 설계는 구름 구간에 muRolling(`rollingResistance`)을 **직접** 쓰고, 미끄럼 구간에만 muKinetic을 쓰는 걸로 이 문제를 원천적으로 피한다 — 두 메커니즘이 겹치는 지점이 없다.

## 6. 변경 파일 예상 범위

- `EasyPutt/GolfBall.swift` — `updateForwardWithSlip` 메서드 추가(기존 `updateFromTorque`/기타 코드 변경 없음, 순수 추가).
- `EasyPutt/RangeFinder/PuttRangeFinder.swift` — `simulateForward()` 안 1줄 변경.
- `EasyPuttTests/GolfBallRollingResistanceTests.swift` — 새 테스트 4개 추가.
- 기존 `PuttRangeFinder*Tests.swift`들은 수정 없이 회귀 확인용으로 그대로 실행.

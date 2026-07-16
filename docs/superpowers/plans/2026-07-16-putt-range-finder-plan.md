# 퍼팅 방향 레인지 파인더 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 공 위치와 홀컵 위치를 탭하면, 브루트포스 없이 "이 방향/속도로 치면 홀인한다"는 (direction, speed) 조합의 집합을 빠르게 계산해서 화면에 보여준다.

**Architecture:** 홀컵에서 공 쪽으로 `GolfBall.updateFromTorque`를 음수 `deltaTime`으로 호출해 거슬러 올라가는 백워드 후보 생성 → 같은 메서드를 양수 `deltaTime`으로 재사용해 정방향 재시뮬레이션하고 오차를 기반으로 (direction, speed)를 보정하는 반복 검증. 지형 데이터는 새 스캔 파이프라인 없이, 기존에 검증된 `ARRaycastQuery` 기반 raycast를 공→홀컵 탭 사이에 화면 여러 지점(3x3)으로 반복 호출해서 얻는 (좌표, 법선벡터) 원시 리스트로 대체한다.

**Tech Stack:** Swift, simd, ARKit(`ARRaycastQuery`), XCTest.

## Global Constraints

- 이번 스펙에서 `Tile`/`TileGrid` 클래스는 쓰지 않는다 (설계 문서 Non-goals).
- `GolfBall.updateFromTorque`의 미끄러짐→구름 전환 로직(`muStatic`/`muKinetic`, 토크)은 그대로 두고, 구름저항 항만 추가한다.
- `ARWorldTrackingConfiguration.sceneReconstruction`은 켜지 않는다 — 상시 전체 환경 메쉬 재구성은 이번 기능에 필요한 "몇 개의 법선벡터"에 비해 리소스 부담이 과하다고 판단해 배제한다 (대화에서 합의됨, 기존 코드에서도 성능 우려로 주석 처리되어 있었음).
- 성공 판정(홀인)은 항상 수평(XZ) 2D 평면에서: 경로가 홀컵 좌표로부터 캡처 반경(≈3.3cm, 튜닝 파라미터) 이내로 지나가면 성공.
- 백워드 후보 생성은 공-홀컵 직선에 수직이고 공 위치를 지나는 선을 넘으면 종료한다 — 그 지점의 (속도, 방향)이 최초 후보가 되고, "얼마나 가까우면 성공인지"는 정밀검증의 캡처 반경 하나로만 판단한다 (백워드 단계에는 별도 반경 체크를 두지 않는다).
- 백워드/정방향 모두 `GolfBall.updateFromTorque`를 그대로(부호만 다르게) 재사용하므로, 회전 상태는 항상 매 시뮬레이션 시작 시 `GolfBall.init`의 기본값(0)에서 새로 시작한다 — 별도의 "회전 경계조건 강제" 코드는 필요 없다.
- ML 기반 이미지 인식, 안드로이드/ARCore 포팅은 이번 계획 범위 밖이다.
- 참고 설계 문서: `docs/superpowers/specs/2026-07-15-putt-range-finder-design.md`

---

## Task 1: GolfBall에 구름저항 + 최대경사방향 헬퍼 추가

**Files:**
- Modify: `EasyPutt/GolfBall.swift`
- Test: `EasyPuttTests/GolfBallRollingResistanceTests.swift` (신규)

**Interfaces:**
- Produces: `GolfBall.rollingResistance: Float` (인스턴스 프로퍼티, 기본값 `0.35`), `GolfBall.updateFromTorque(deltaTime:surfaceNormal:)`가 이제 병진속도에 구름저항을 반영함 (기존 시그니처 그대로, 동작만 보완). `GolfBall.steepestDescentDirection(surfaceNormal:) -> simd_float3` (static 메서드, 신규).

- [ ] **Step 1: 구름저항 실패 테스트 작성**

`EasyPuttTests/GolfBallRollingResistanceTests.swift` 새로 생성:

```swift
import XCTest
import simd
@testable import EasyPutt

final class GolfBallRollingResistanceTests: XCTestCase {

    func testBallOnFlatGroundEventuallyStops() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(1.0, 0, 0))
        ball.rollingResistance = 0.5
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.05

        var stopped = false
        for _ in 0..<200 {
            ball.updateFromTorque(deltaTime: dt, surfaceNormal: flatNormal)
            if ball.hasStopped {
                stopped = true
                break
            }
        }

        XCTAssertTrue(stopped, "flat-ground ball should eventually stop under rolling resistance")
    }

    func testRollingResistanceDeceleratesTranslationalSpeed() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(1.0, 0, 0))
        ball.rollingResistance = 0.5
        let flatNormal = simd_float3(0, 1, 0)

        ball.updateFromTorque(deltaTime: 0.1, surfaceNormal: flatNormal)

        // Expected speed after one step: 1.0 - rollingResistance * dt = 1.0 - 0.05 = 0.95
        // (flat ground: gravityTangent is zero, so only rolling resistance acts.)
        XCTAssertEqual(simd_length(ball.velocity), 0.95, accuracy: 0.001)
    }

    func testSteepestDescentDirectionOnTiltedSurface() {
        // Normal tilted toward +x means the surface descends toward +x.
        let normal = simd_normalize(simd_float3(0.2, 1, 0))
        let direction = GolfBall.steepestDescentDirection(surfaceNormal: normal)

        XCTAssertGreaterThan(direction.x, 0, "descent direction should point toward +x for this tilt")
        XCTAssertEqual(direction.y, 0, accuracy: 0.001, "descent direction should be horizontal")
        XCTAssertEqual(simd_length(direction), 1.0, accuracy: 0.001)
    }

    func testSteepestDescentDirectionOnFlatSurfaceIsZero() {
        let normal = simd_float3(0, 1, 0)
        let direction = GolfBall.steepestDescentDirection(surfaceNormal: normal)
        XCTAssertEqual(simd_length(direction), 0, accuracy: 0.0001, "flat ground has no descent direction")
    }
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/GolfBallRollingResistanceTests`

Expected: FAIL — `rollingResistance` 프로퍼티와 `steepestDescentDirection` 메서드가 없어서 컴파일 에러.

- [ ] **Step 3: GolfBall.swift에 구름저항과 헬퍼 구현**

`EasyPutt/GolfBall.swift`에서 물리 속성 선언부에 프로퍼티 추가:

```swift
    // 물리 속성
    private let radius: Float = 0.021
    private let mass: Float = 0.045
    private let muStatic: Float = 0.4
    private let muKinetic: Float = 0.2
    private let gravity = simd_float3(0, -9.8, 0)
    /// 구름저항(rolling resistance) 감속 계수 — 그린 속도(스팀프값)에 해당하는 튜닝 파라미터.
    var rollingResistance: Float = 0.35
```

`updateFromTorque(deltaTime:surfaceNormal:)`의 병진속도 갱신 직후(각속도/토크 계산 이전)에 구름저항 적용:

```swift
    func updateFromTorque(deltaTime dt: Float, surfaceNormal n: simd_float3) {
        let gravityParallel = gravity - simd_dot(gravity, n) * n
        let accelMag = simd_length(gravityParallel) * (5.0 / 7.0)
        let accelDir = simd_normalize(gravityParallel)
        let acceleration = accelDir * accelMag
      
        // 선속도 및 위치 업데이트
        velocity += acceleration * dt
        applyRollingResistance(deltaTime: dt)
        position += velocity * dt

        guard simd_length(velocity) > 0.0001 else { return }
        // ... 이하 토크/회전 계산은 기존 그대로 ...
```

같은 파일, `GolfBall` 클래스 안에 새 private 메서드와 static 메서드 추가 (`updateFromTorque` 바로 아래):

```swift
    /// 구름저항을 병진속도에 반영한다. `dt`가 음수(역방향 계산)면 자연히 반대로
    /// 작용해 속도가 늘어난다 — 별도의 "역방향" 분기 없이 동일한 식으로 양방향을 다룬다.
    private func applyRollingResistance(deltaTime dt: Float) {
        let speed = simd_length(velocity)
        guard speed > 0.0001 else {
            velocity = .zero
            return
        }
        let newSpeed = max(0, speed - rollingResistance * dt)
        velocity = simd_normalize(velocity) * newSpeed
    }

    /// 주어진 법선벡터에서 중력을 접평면에 투영해 얻는 최대 경사(내리막) 방향.
    /// 평평한 면(법선이 정확히 위를 향함)에서는 경사 방향이 없으므로 `.zero`를 반환한다.
    static func steepestDescentDirection(surfaceNormal n: simd_float3) -> simd_float3 {
        let gravity = simd_float3(0, -9.8, 0)
        let normal = simd_normalize(n)
        let gravityParallel = gravity - simd_dot(gravity, normal) * normal
        guard simd_length(gravityParallel) > 0.0001 else { return .zero }
        return simd_normalize(gravityParallel)
    }
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/GolfBallRollingResistanceTests`

Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/GolfBall.swift EasyPuttTests/GolfBallRollingResistanceTests.swift
git commit -m "GolfBall에 구름저항과 최대경사방향 헬퍼 추가"
```

---

## Task 2: TerrainSampleStore (좌표+법선벡터 원시 리스트, 최근접 탐색)

**Files:**
- Create: `EasyPutt/RangeFinder/TerrainSampleStore.swift`
- Test: `EasyPuttTests/TerrainSampleStoreTests.swift`

**Interfaces:**
- Consumes: 없음 (독립 타입, `simd`만 사용).
- Produces: `struct TerrainSample { let position: simd_float3; let normal: simd_float3 }`, `final class TerrainSampleStore { func add(position: simd_float3, normal: simd_float3); func removeAll(); func nearestNormal(to position: simd_float3) -> simd_float3?; var isEmpty: Bool; var count: Int }`

- [ ] **Step 1: 실패 테스트 작성**

`EasyPuttTests/TerrainSampleStoreTests.swift` 새로 생성:

```swift
import XCTest
import simd
@testable import EasyPutt

final class TerrainSampleStoreTests: XCTestCase {

    func testEmptyStoreReturnsNil() {
        let store = TerrainSampleStore()
        XCTAssertNil(store.nearestNormal(to: .zero))
        XCTAssertTrue(store.isEmpty)
    }

    func testReturnsNearestSampleByHorizontalDistance() {
        let store = TerrainSampleStore()
        store.add(position: simd_float3(0, 0, 0), normal: simd_float3(0, 1, 0))
        store.add(position: simd_float3(10, 0, 0), normal: simd_float3(1, 0, 0))

        let result = store.nearestNormal(to: simd_float3(9, 5, 0))

        XCTAssertEqual(result, simd_float3(1, 0, 0))
    }

    func testIgnoresHeightDifferenceWhenFindingNearest() {
        let store = TerrainSampleStore()
        store.add(position: simd_float3(0, 100, 0), normal: simd_float3(0, 1, 0))
        store.add(position: simd_float3(1, 0, 0), normal: simd_float3(1, 0, 0))

        // (0, 100, 0) is horizontally (XZ) closer to the query point than (1, 0, 0),
        // even though it is far away vertically.
        let result = store.nearestNormal(to: simd_float3(0.1, 0, 0))

        XCTAssertEqual(result, simd_float3(0, 1, 0))
    }

    func testCountIsEmptyAndRemoveAll() {
        let store = TerrainSampleStore()
        XCTAssertEqual(store.count, 0)
        store.add(position: .zero, normal: simd_float3(0, 1, 0))
        XCTAssertEqual(store.count, 1)
        XCTAssertFalse(store.isEmpty)
        store.removeAll()
        XCTAssertEqual(store.count, 0)
        XCTAssertTrue(store.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/TerrainSampleStoreTests`

Expected: FAIL — `TerrainSampleStore` 타입이 없어서 컴파일 에러.

- [ ] **Step 3: TerrainSampleStore 구현**

`EasyPutt/RangeFinder/TerrainSampleStore.swift` 새로 생성:

```swift
//
//  TerrainSampleStore.swift
//  EasyPutt
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

    func nearestNormal(to position: simd_float3) -> simd_float3? {
        guard !samples.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistanceSquared = horizontalDistanceSquared(position, samples[0].position)
        for index in 1..<samples.count {
            let distanceSquared = horizontalDistanceSquared(position, samples[index].position)
            if distanceSquared < bestDistanceSquared {
                bestDistanceSquared = distanceSquared
                bestIndex = index
            }
        }
        return samples[bestIndex].normal
    }

    private func horizontalDistanceSquared(_ a: simd_float3, _ b: simd_float3) -> Float {
        let dx = a.x - b.x
        let dz = a.z - b.z
        return dx * dx + dz * dz
    }
}
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/TerrainSampleStoreTests`

Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/RangeFinder/TerrainSampleStore.swift EasyPuttTests/TerrainSampleStoreTests.swift
git commit -m "TerrainSampleStore 추가 (좌표+법선벡터 최근접 탐색)"
```

---

## Task 3: 백워드 후보 생성 (PuttRangeFinder.backwardCandidate)

**Files:**
- Create: `EasyPutt/RangeFinder/PuttRangeFinder.swift`
- Test: `EasyPuttTests/PuttRangeFinderBackwardTests.swift`

**Interfaces:**
- Consumes: `TerrainSampleStore.nearestNormal(to:)` (Task 2), `GolfBall(initialPosition:initialVelocity:)` / `GolfBall.updateFromTorque(deltaTime:surfaceNormal:)` / `GolfBall.steepestDescentDirection(surfaceNormal:)` / `GolfBall.rollingResistance` (Task 1).
- Produces: `struct PuttSolution { let direction: simd_float3; let speed: Float }`, `struct PuttRangeFinderConfig { var rollingResistance: Float; var deltaTime: Float; var maxBackwardSteps: Int; var maxForwardSteps: Int; var captureRadius: Float; var holeCrossingSpeeds: [Float]; var maxCorrectionIterations: Int; var directionGain: Float; var speedGain: Float; var naturalDirectionAlignmentThreshold: Float }` (기본값 포함, `static let default`), `final class PuttRangeFinder { init(terrain: TerrainSampleStore, config: PuttRangeFinderConfig = .default); func backwardCandidate(holePosition: simd_float3, ballPosition: simd_float3, holeCrossingSpeed: Float) -> PuttSolution? }` — 이후 Task 4/5에서 같은 클래스에 메서드를 더 추가한다.

- [ ] **Step 1: 실패 테스트 작성**

`EasyPuttTests/PuttRangeFinderBackwardTests.swift` 새로 생성:

```swift
import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderBackwardTests: XCTestCase {

    /// 완만한 등경사 지형(홀컵 방향으로 내리막)을 만든다 — x가 커질수록 낮아짐.
    private func makeGentleSlopeTerrain() -> TerrainSampleStore {
        let store = TerrainSampleStore()
        let normal = simd_normalize(simd_float3(0.03, 1, 0)) // ~1.7도, 내리막은 +x 방향
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: normal)
                z += 0.2
            }
            x += 0.2
        }
        return store
    }

    func testBackwardCandidateFindsPlausibleDirectionAndSpeed() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        // 공에서 홀컵으로 가려면 +x 방향으로 쳐야 한다 (내리막과 일치).
        XCTAssertGreaterThan(candidate.direction.x, 0.9)
        // 완만한 내리막에서 2.5m 거리를 커버하려면 어느 정도 속도가 필요하다 (느슨한 범위).
        XCTAssertGreaterThan(candidate.speed, 0.1)
        XCTAssertLessThan(candidate.speed, 5.0)
    }

    func testBackwardCandidateReturnsNilWithoutTerrainData() {
        let emptyTerrain = TerrainSampleStore()
        let finder = PuttRangeFinder(terrain: emptyTerrain)
        let candidate = finder.backwardCandidate(
            holePosition: simd_float3(1.5, 0, 0),
            ballPosition: simd_float3(-1.0, 0, 0),
            holeCrossingSpeed: 0.08
        )
        XCTAssertNil(candidate)
    }

    func testBackwardCandidateReturnsNilForZeroOrNegativeCrossingSpeed() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let candidate = finder.backwardCandidate(
            holePosition: simd_float3(1.5, 0, 0),
            ballPosition: simd_float3(-1.0, 0, 0),
            holeCrossingSpeed: 0
        )
        XCTAssertNil(candidate)
    }

    func testBackwardCandidateOnFlatGroundFallsBackToStraightLine() {
        let store = TerrainSampleStore()
        let flatNormal = simd_float3(0, 1, 0)
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: flatNormal)
                z += 0.2
            }
            x += 0.2
        }
        let finder = PuttRangeFinder(terrain: store)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        // 평지에는 자연스러운 낙하 방향이 없으므로, 공→홀컵 직선 방향을 폴백으로 쓴다.
        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        XCTAssertEqual(candidate.direction.x, 1.0, accuracy: 0.01)
        XCTAssertEqual(candidate.direction.z, 0.0, accuracy: 0.01)
    }

    func testBackwardCandidateOnUphillPuttFallsBackToStraightLine() {
        // makeGentleSlopeTerrain()의 내리막은 항상 +x 방향이다. 홀컵을 공보다
        // -x쪽(더 높은 쪽)에 두면, 홀컵에서의 최대 경사(+x)는 공 반대쪽을 향하게 된다 —
        // 오르막 퍼팅. 이 경우 최대 경사 대신 공→홀컵 직선을 써야 한다.
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(-1.5, 0, 0)
        let ball = simd_float3(1.0, 0, 0)

        let candidate = finder.backwardCandidate(holePosition: hole, ballPosition: ball, holeCrossingSpeed: 0.08)

        XCTAssertNotNil(candidate)
        guard let candidate = candidate else { return }
        // 공에서 홀컵으로 가려면 -x 방향(오르막)으로 쳐야 한다.
        XCTAssertLessThan(candidate.direction.x, -0.9)
    }
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderBackwardTests`

Expected: FAIL — `PuttRangeFinder`/`PuttSolution`/`PuttRangeFinderConfig` 타입이 없어서 컴파일 에러.

- [ ] **Step 3: PuttRangeFinder와 backwardCandidate 구현**

`EasyPutt/RangeFinder/PuttRangeFinder.swift` 새로 생성:

```swift
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
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderBackwardTests`

Expected: PASS (5 tests). `testBackwardCandidateFindsPlausibleDirectionAndSpeed`가 실패하면(예: direction.x가 기대와 다르면) `GolfBall.steepestDescentDirection`의 부호나 `updateFromTorque`에 음수 `deltaTime`을 넣었을 때의 동작을 다시 점검한다. `testBackwardCandidateOnUphillPuttFallsBackToStraightLine`이 실패하면 `naturalDirectionAlignmentThreshold` 비교 부등호나 `straightLineDirection`의 부호를 다시 점검한다.

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/RangeFinder/PuttRangeFinder.swift EasyPuttTests/PuttRangeFinderBackwardTests.swift
git commit -m "PuttRangeFinder 백워드 후보 생성 추가"
```

---

## Task 4: 정방향 검증 + 오차 보정 반복 (PuttRangeFinder.verify)

**Files:**
- Modify: `EasyPutt/RangeFinder/PuttRangeFinder.swift`
- Test: `EasyPuttTests/PuttRangeFinderVerifyTests.swift`

**Interfaces:**
- Consumes: Task 3의 `PuttSolution`, `PuttRangeFinderConfig`, `GolfBall.updateFromTorque` (양수 `deltaTime`).
- Produces: `PuttRangeFinder.verify(_ candidate: PuttSolution, ballPosition: simd_float3, holePosition: simd_float3) -> PuttSolution?`

- [ ] **Step 1: 실패 테스트 작성**

`EasyPuttTests/PuttRangeFinderVerifyTests.swift` 새로 생성:

```swift
import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderVerifyTests: XCTestCase {

    private func makeGentleSlopeTerrain() -> TerrainSampleStore {
        let store = TerrainSampleStore()
        let normal = simd_normalize(simd_float3(0.03, 1, 0))
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: normal)
                z += 0.2
            }
            x += 0.2
        }
        return store
    }

    func testVerifyCorrectsADeliberatelyWrongCandidate() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        // 의도적으로 부정확한 후보: 방향이 옆으로 치우쳐 있고 속도도 다름.
        let wrongCandidate = PuttSolution(direction: simd_normalize(simd_float3(1.0, 0, 0.3)), speed: 0.5)

        let verified = finder.verify(wrongCandidate, ballPosition: ball, holePosition: hole)

        XCTAssertNotNil(verified, "보정 반복이 수렴해서 유효한 candidate를 반환해야 한다")
    }

    func testVerifyReturnsNilWhenTerrainRunsOut() {
        // 공 근처에만 지형 샘플이 있고 홀컵 근처엔 없어서, 시뮬레이션이 중간에 끊기는 상황.
        let store = TerrainSampleStore()
        store.add(position: simd_float3(-1.0, 0, 0), normal: simd_float3(0, 1, 0))
        let finder = PuttRangeFinder(terrain: store)

        let candidate = PuttSolution(direction: simd_float3(1, 0, 0), speed: 1.0)
        let verified = finder.verify(candidate, ballPosition: simd_float3(-1.0, 0, 0), holePosition: simd_float3(100, 0, 0))

        XCTAssertNil(verified)
    }
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests`

Expected: FAIL — `verify` 메서드가 없어서 컴파일 에러.

- [ ] **Step 3: verify 메서드 구현**

`EasyPutt/RangeFinder/PuttRangeFinder.swift`의 `PuttRangeFinder` 클래스 안, `backwardCandidate` 아래에 추가:

```swift
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
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests`

Expected: PASS (2 tests). `testVerifyCorrectsADeliberatelyWrongCandidate`가 수렴하지 못하면, `directionGain`/`speedGain` 부호나 크기를 조정한다 — 부호가 반대로 되어 있으면 오차가 매 반복마다 커진다(발산). 부호가 맞는데 느리게 수렴하면 `maxCorrectionIterations`를 늘리거나 게인을 키운다.

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/RangeFinder/PuttRangeFinder.swift EasyPuttTests/PuttRangeFinderVerifyTests.swift
git commit -m "PuttRangeFinder 정방향 검증 + 오차 보정 반복 추가"
```

---

## Task 5: 전체 오케스트레이션 (findSolutions)

**Files:**
- Modify: `EasyPutt/RangeFinder/PuttRangeFinder.swift`
- Test: `EasyPuttTests/PuttRangeFinderEndToEndTests.swift`

**Interfaces:**
- Consumes: Task 3의 `backwardCandidate`, Task 4의 `verify`, `PuttRangeFinderConfig.holeCrossingSpeeds`.
- Produces: `PuttRangeFinder.findSolutions(ballPosition: simd_float3, holePosition: simd_float3) -> [PuttSolution]`

- [ ] **Step 1: 실패 테스트 작성**

`EasyPuttTests/PuttRangeFinderEndToEndTests.swift` 새로 생성:

```swift
import XCTest
import simd
@testable import EasyPutt

final class PuttRangeFinderEndToEndTests: XCTestCase {

    private func makeGentleSlopeTerrain() -> TerrainSampleStore {
        let store = TerrainSampleStore()
        let normal = simd_normalize(simd_float3(0.03, 1, 0))
        var x: Float = -3.0
        while x <= 3.0 {
            var z: Float = -3.0
            while z <= 3.0 {
                store.add(position: simd_float3(x, 0, z), normal: normal)
                z += 0.2
            }
            x += 0.2
        }
        return store
    }

    func testFindSolutionsReturnsAtLeastOneVerifiedSolution() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let solutions = finder.findSolutions(ballPosition: ball, holePosition: hole)

        XCTAssertFalse(solutions.isEmpty, "완만한 직선 내리막 지형에서는 최소 하나의 해가 나와야 한다")
        for solution in solutions {
            XCTAssertGreaterThan(solution.direction.x, 0.8, "이 지형에서 해는 대체로 +x(홀컵) 방향을 향해야 한다")
        }
    }

    func testFindSolutionsReturnsEmptyWithoutTerrainData() {
        let finder = PuttRangeFinder(terrain: TerrainSampleStore())
        let solutions = finder.findSolutions(ballPosition: simd_float3(-1, 0, 0), holePosition: simd_float3(1.5, 0, 0))
        XCTAssertTrue(solutions.isEmpty)
    }
}
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderEndToEndTests`

Expected: FAIL — `findSolutions` 메서드가 없어서 컴파일 에러.

- [ ] **Step 3: findSolutions 구현**

`EasyPutt/RangeFinder/PuttRangeFinder.swift`의 `PuttRangeFinder` 클래스 안, `verify` 아래에 추가:

```swift
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
```

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderEndToEndTests`

Expected: PASS (2 tests)

- [ ] **Step 5: 전체 RangeFinder 테스트 스위트 실행**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/GolfBallRollingResistanceTests -only-testing:EasyPuttTests/TerrainSampleStoreTests -only-testing:EasyPuttTests/PuttRangeFinderBackwardTests -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests -only-testing:EasyPuttTests/PuttRangeFinderEndToEndTests`

Expected: PASS (전체)

- [ ] **Step 6: 커밋**

```bash
git add EasyPutt/RangeFinder/PuttRangeFinder.swift EasyPuttTests/PuttRangeFinderEndToEndTests.swift
git commit -m "PuttRangeFinder 오케스트레이션(findSolutions) 추가"
```

---

## Task 6: 공→홀컵 탭 사이 지형 샘플 수집 (다중 지점 raycast)

이 태스크는 ARKit 세션이 실제로 돌아가는 실기기에서만 확인 가능하다 (시뮬레이터는 카메라 트래킹이 없어 ARKit 코드가 동작하지 않음, README의 "요구 사항" 참고). XCTest로 검증하지 않고, Step 마지막에 실기기 수동 확인 절차를 둔다.

`ArViewModel.performRaycast(at:)`는 재사용하지 않는다 — 그 메서드의 현실 세계(ARKit) raycast 부분은 실제로는 항상 카메라 정면 방향만 쏘고 전달받은 `screenPoint`를 쓰지 않는다 (기존 코드의 특성, 그대로 둠). 여러 화면 지점을 실제로 다르게 raycast하려면 화면 좌표별로 광선의 원점/방향이 달라지는 `arView.screenToWorldRay(_:)`(파일 하단에 이미 정의된 `ARView` extension)를 직접 써야 한다.

**Files:**
- Modify: `EasyPutt/ArViewModel.swift`

**Interfaces:**
- Consumes: `ArView.screenToWorldRay(_:) -> (origin: simd_float3, direction: simd_float3)?` (기존 extension, `ArViewModel.swift` 파일 하단), `ArViewModel.isCollectingTerrainSamples` (신규, 아래 Step 1), `arView.cameraTransform.translation` (기존 ARKit API, 추가 raycast 비용 없이 카메라 위치를 바로 얻음).
- Produces: `ArViewModel.terrainSamples: TerrainSampleStore` (신규), `ArViewModel.isCollectingTerrainSamples: Bool` (신규), `ArViewModel.terrainSampleGridResolution: Int` (신규, 기본값 3 — N×N 격자), `ArViewModel.terrainSampleGridSpan: ClosedRange<CGFloat>` (신규, 기본값 `0.2...0.8` — 화면 폭 기준 격자가 퍼지는 범위), `ArViewModel.terrainSampleMinSpacing: Float` (신규, 기본값 0.5 — 수집 지점 간 최소 거리, 미터), `ArViewModel.startCollectingTerrainSamples()`, `ArViewModel.stopCollectingTerrainSamples()`, `ArViewModel.collectTerrainSamples()`.

- [ ] **Step 1: ArViewModel에 샘플 저장소, 수집 상태, 튜닝 파라미터 추가**

`EasyPutt/ArViewModel.swift`의 프로퍼티 선언부(예: `@Published var tileGrid : TileGrid?` 근처)에 추가:

```swift
    let terrainSamples = TerrainSampleStore()
    var isCollectingTerrainSamples: Bool = false
    /// 화면을 N x N 격자로 나눠 raycast한다 (N = 이 값). 촘촘하게 하려면 늘린다.
    var terrainSampleGridResolution: Int = 3
    /// 격자 지점들이 화면 폭 기준 어느 범위에 퍼져 있는지 (0=왼쪽 끝, 1=오른쪽 끝).
    /// 넓히면(예: 0.05...0.95) 더 넓은 실제 폭을 커버한다.
    var terrainSampleGridSpan: ClosedRange<CGFloat> = 0.2...0.8
    /// 새 격자 수집을 실행하려면 카메라가 "지금까지의 모든 수집 지점"으로부터
    /// 최소 이만큼(미터) 떨어져 있어야 한다 — 제자리 정체나 경로가 교차할 때
    /// 중복 수집을 막는다.
    var terrainSampleMinSpacing: Float = 0.5
    private var terrainSampleCollectionCenters: [simd_float3] = []
```

- [ ] **Step 2: 수집 시작/종료 메서드 추가**

`ArViewModel` 클래스 안, `requestRaycastUpdate()` 근처에 추가:

```swift
    func startCollectingTerrainSamples() {
        terrainSamples.removeAll()
        terrainSampleCollectionCenters.removeAll()
        isCollectingTerrainSamples = true
    }

    func stopCollectingTerrainSamples() {
        isCollectingTerrainSamples = false
    }
```

- [ ] **Step 3: 거리 게이트 + 다중 지점 raycast로 샘플 수집하는 메서드 추가**

`ArViewModel` 클래스 안, `stopCollectingTerrainSamples()` 아래에 추가:

```swift
    /// 카메라가 지금까지의 모든 수집 지점으로부터 `terrainSampleMinSpacing` 이상
    /// 떨어져 있을 때만, 화면을 N x N 격자로 나눠 각 지점에서 raycast해
    /// (좌표, 법선벡터) 샘플을 모은다. `sceneReconstruction`처럼 상시 전체
    /// 환경을 재구성하지 않고, 필요한 순간에만 가볍게 여러 지점을 훑는다.
    func collectTerrainSamples() {
        guard isCollectingTerrainSamples, let arView = self.arView else { return }

        let cameraPosition = arView.cameraTransform.translation
        let tooClose = terrainSampleCollectionCenters.contains {
            simd_distance($0, cameraPosition) < terrainSampleMinSpacing
        }
        guard !tooClose else { return }
        terrainSampleCollectionCenters.append(cameraPosition)

        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0, terrainSampleGridResolution > 0 else { return }

        let fractions: [CGFloat] = (0..<terrainSampleGridResolution).map { index in
            guard terrainSampleGridResolution > 1 else { return (terrainSampleGridSpan.lowerBound + terrainSampleGridSpan.upperBound) / 2 }
            let t = CGFloat(index) / CGFloat(terrainSampleGridResolution - 1)
            return terrainSampleGridSpan.lowerBound + t * (terrainSampleGridSpan.upperBound - terrainSampleGridSpan.lowerBound)
        }

        for xFraction in fractions {
            for yFraction in fractions {
                let screenPoint = CGPoint(x: bounds.width * xFraction, y: bounds.height * yFraction)
                guard let ray = arView.screenToWorldRay(screenPoint) else { continue }
                let query = ARRaycastQuery(
                    origin: ray.origin,
                    direction: normalize(ray.direction),
                    allowing: .estimatedPlane,
                    alignment: .any
                )
                guard let hit = arView.session.raycast(query).first else { continue }
                let transform = hit.worldTransform
                let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                let normal = simd_make_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
                terrainSamples.add(position: position, normal: normal)
            }
        }
    }
```

(예: `terrainSampleGridResolution = 3`, `terrainSampleGridSpan = 0.2...0.8`이면 fractions는 `[0.2, 0.5, 0.8]`이 되어 이전과 동일하게 동작한다 — 기본값은 하위 호환.)

- [ ] **Step 4: 기존 raycast 루프에서 매 틱마다 수집 호출**

`EasyPutt/ArViewModel.swift`의 `init()` 안, `updateSubject.throttle(...).sink { ... }` 클로저에서 raycast를 수행하는 다음 줄:

```swift
                (self.arRaycastResult, self.vrRaycastResult) = self.performRaycast(at :center )
```

바로 아래에 추가:

```swift
                self.collectTerrainSamples()
```

- [ ] **Step 5: 컴파일 확인**

Run: `xcodebuild build -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED (ARKit 심볼 자체는 시뮬레이터에서도 링크되며, 실행 시에만 카메라 트래킹이 안 될 뿐이므로 빌드는 통과해야 한다)

- [ ] **Step 6: 실기기 수동 확인**

라이다 탑재 iPhone에 실행한 뒤, `startCollectingTerrainSamples()`를 호출하는 UI가 아직 없으므로(Task 7에서 연결) 이 단계에서는 임시로 앱 실행 직후 `isCollectingTerrainSamples = true`를 코드에서 강제로 켜두고 몇 초 뒤 `terrainSamples.count`를 `print`로 찍어, 값이 (틱당 최대 9개씩) 증가하는지 확인한다. Task 7 완료 후 실제 탭 플로우로 다시 검증한다.

- [ ] **Step 7: 커밋**

```bash
git add EasyPutt/ArViewModel.swift
git commit -m "공-홀컵 탭 사이 다중 지점 raycast로 지형 샘플 수집 추가"
```

---

## Task 7: 탭 플로우 변경 + 결과 표시 UI

이 태스크도 ARKit/RealityKit 실행이 필요해 실기기 수동 확인으로 검증한다.

**Files:**
- Modify: `EasyPutt/ArViewContainer.swift`
- Modify: `EasyPutt/ContentView2.swift`
- Modify: `EasyPutt/ArViewModel.swift`

**Interfaces:**
- Consumes: Task 5의 `PuttRangeFinder.findSolutions(ballPosition:holePosition:)`, Task 6의 `ArViewModel.terrainSamples` / `startCollectingTerrainSamples()` / `stopCollectingTerrainSamples()`.
- Produces: `ArViewModel.ballPosition: simd_float3?`, `ArViewModel.holePosition: simd_float3?`, `ArViewModel.rangeFinderSolutions: [PuttSolution]` (`@Published`), `ArViewModel.ballToHoleDistance: Float?` (`@Published`), `ArViewModel.runRangeFinder()`, `ArViewModel.captureBallSubject` / `captureHoleSubject: PassthroughSubject<Void, Never>`.

- [ ] **Step 1: ArViewModel에 공/홀컵 위치, 결과 상태, 트리거 추가**

`EasyPutt/ArViewModel.swift`의 프로퍼티 선언부에 추가:

```swift
    var ballPosition: simd_float3?
    var holePosition: simd_float3?
    @Published var rangeFinderSolutions: [PuttSolution] = []
    @Published var ballToHoleDistance: Float?

    let captureBallSubject = PassthroughSubject<Void, Never>()
    let captureHoleSubject = PassthroughSubject<Void, Never>()
```

- [ ] **Step 2: runRangeFinder() 추가**

`ArViewModel` 클래스 안, `collectTerrainSamples()` 아래에 추가:

```swift
    func runRangeFinder() {
        guard let ball = ballPosition, let hole = holePosition else {
            print("runRangeFinder: ball 또는 hole 위치가 없음")
            return
        }
        ballToHoleDistance = simd_distance(
            simd_float3(ball.x, 0, ball.z),
            simd_float3(hole.x, 0, hole.z)
        )
        let finder = PuttRangeFinder(terrain: terrainSamples)
        rangeFinderSolutions = finder.findSolutions(ballPosition: ball, holePosition: hole)
        print("runRangeFinder: \(rangeFinderSolutions.count)개 solution 발견")
    }
```

- [ ] **Step 3: ArViewContainer의 Coordinator에 캡처 로직과 구독 추가**

기존 `handleTap(_:)`(수동 퍼팅 재생용)은 그대로 두고 건드리지 않는다. `EasyPutt/ArViewContainer.swift`의 `Coordinator` 클래스 안, `handleTap(_:)` 아래에 추가:

```swift
        func captureBallPosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureBallPosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.ballPosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.startCollectingTerrainSamples()
        }

        func captureHolePosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureHolePosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.holePosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.stopCollectingTerrainSamples()
            parent.arViewModel.runRangeFinder()
        }

        func subscribeToCaptureTriggers() {
            parent.arViewModel.captureBallSubject
                .sink { [weak self] in self?.captureBallPosition() }
                .store(in: &cancellables)
            parent.arViewModel.captureHoleSubject
                .sink { [weak self] in self?.captureHolePosition() }
                .store(in: &cancellables)
        }
```

`makeUIView(context:)`의 기존 탭 제스처 등록 줄:

```swift
        arViewModel.arView?.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap)))
```

바로 아래에 추가:

```swift
        context.coordinator.subscribeToCaptureTriggers()
```

- [ ] **Step 4: ContentView2에 Ball/Hole 버튼과 결과 표시 추가**

`EasyPutt/ContentView2.swift`의 `.safeAreaInset(edge: .bottom)` 툴바, 기존 `ActionButton("Start", ...)` 앞에 두 버튼 추가:

```swift
                ActionButton(title: "Ball", color: .green) {
                    arViewModel.captureBallSubject.send()
                }

                ActionButton(title: "Hole", color: .red) {
                    arViewModel.captureHoleSubject.send()
                }
```

결과 표시는 기존 "타일 상태 표시 (하단)" `VStack` 위에 추가:

```swift
            if let distance = arViewModel.ballToHoleDistance {
                VStack {
                    Text("거리: \(distance, specifier: "%.2f")m")
                    Text("유효 방향: \(arViewModel.rangeFinderSolutions.count)개")
                    ForEach(Array(arViewModel.rangeFinderSolutions.enumerated()), id: \.offset) { _, solution in
                        Text("speed \(solution.speed, specifier: "%.2f") / dir (\(solution.direction.x, specifier: "%.2f"), \(solution.direction.z, specifier: "%.2f"))")
                            .font(.caption2)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.top, 60)
            }
```

(방향/거리를 부채꼴이나 슬라이더 하이라이트로 시각화하는 건 이번 태스크 범위 밖 — 우선 텍스트로 값만 노출해 실기기에서 알고리즘 결과가 맞는지부터 확인한다. 시각화는 이 텍스트 출력이 실기기에서 그럴듯한 값을 낸다고 확인된 뒤 별도 후속 작업으로 진행한다.)

- [ ] **Step 5: 빌드 확인**

Run: `xcodebuild build -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: 실기기 수동 확인**

라이다 탑재 iPhone에서:
1. 앱 실행, 퍼팅 그린(또는 바닥) 위에서 카메라를 비춘다.
2. 공 위치를 조준하고 **Ball** 버튼을 탭한다.
3. 카메라를 자연스럽게 홀컵 쪽으로 이동시킨다 (이 사이 `terrainSamples`가 채워짐).
4. 홀컵 위치를 조준하고 **Hole** 버튼을 탭한다 — 이 시점에 `runRangeFinder()`가 자동 실행된다.
5. 화면 하단에 거리(m)와 solution 개수/값이 표시되는지 확인한다.
6. 완전히 평평한 바닥이나 오르막 퍼팅(홀컵이 공보다 높은 경우)에서 테스트해도 solution이 0개가 아니어야 한다 — Task 3의 `naturalDirectionAlignmentThreshold` 폴백 덕분에 이런 경우엔 공→홀컵 직선 방향이 후보로 쓰인다. 만약 계속 0개만 나오면 raycast로 얻은 법선벡터 자체가 이상하지 않은지(예: 항상 `(0,1,0)`으로 고정되어 있지 않은지) 먼저 의심한다.

- [ ] **Step 7: 커밋**

```bash
git add EasyPutt/ArViewContainer.swift EasyPutt/ContentView2.swift EasyPutt/ArViewModel.swift
git commit -m "공/홀컵 탭 플로우와 range finder 결과 표시 UI 추가"
```

---

## Self-Review 메모 (계획 작성자 기록용)

- **스펙 커버리지**: 데이터 수집(Task 6, raycast 재사용으로 변경 — 아래 참고), 정방향 엔진 보완(Task 1), 백워드 추적(Task 3), 정밀검증+오차보정(Task 4), 오케스트레이션(Task 5), UI(Task 7) 모두 태스크로 커버됨. 공-홀컵 거리 표시는 Task 7 Step 2/4에 포함.
- **설계 문서와의 차이점**:
  1. 설계 문서는 데이터 수집을 `sceneDepth` 픽셀 이웃 샘플링으로 적었으나, 이 계획은 기존에 이미 검증된 `ARRaycastQuery`(`arView.screenToWorldRay` + `session.raycast`)를 화면 3x3 지점에 반복 호출하는 것으로 변경했다. `sceneReconstruction = .mesh`(전체 환경 상시 메쉬)도 검토했으나, 필요한 데이터양(몇 개의 법선벡터)에 비해 리소스 부담이 크다고 판단해 배제했다 (모두 대화에서 합의됨). "별도 스캔 없이 자연스럽게 샘플이 쌓인다"는 설계 의도는 그대로 유지된다.
  2. 초기 설계의 백워드 추적 "반경 R 이내 도달" 체크를 "공-홀컵 직선에 수직인, 공을 지나는 선을 넘으면 종료"로 단순화했고, "얼마나 가까우면 성공인지"는 Task 4의 `captureRadius` 하나로 통일했다.
  3. 회전/스핀 상태를 백워드 추적 중 별도로 추적하거나 경계조건에서 강제로 0으로 리셋하는 로직은 필요 없다 — 백워드/정방향 모두 매번 새 `GolfBall` 인스턴스를 만들어 `updateFromTorque`(부호만 다르게)를 호출하므로, `GolfBall.init`의 기본값(각속도 0)이 자연스럽게 그 역할을 한다.
  4. (대화 중 추가 합의) 백워드 추적의 시작 방향으로 홀컵에서의 최대 경사(`steepestDescentDirection`)를 그대로 쓰면, 평지(경사가 없는 경우)나 오르막 퍼팅(최대 경사가 공 반대쪽을 향하는 경우)에서 후보가 전혀 나오지 않는 문제가 있었다. Task 3에 `naturalDirectionAlignmentThreshold`(기본 `cos(60°)`)를 추가해, 최대 경사 방향이 공→홀컵 직선과 60도 넘게 벌어지면(평지의 `.zero`도 이 조건에 자연히 포함됨) 공→홀컵 직선 자체를 시작 방향으로 쓰도록 폴백을 통일했다 — "홀컵 기준 뒤쪽" 방향에서는 후보를 찾지 않는다는 원칙.
- **타입/시그니처 일관성**: `PuttSolution { direction, speed }`, `PuttRangeFinderConfig`, `PuttRangeFinder(terrain:config:)` 전 태스크에서 동일하게 사용됨을 확인. `TerrainSampleStore.nearestNormal(to:)`가 Task 2~6 전체에서 유일한 법선벡터 조회 경로임을 확인 (`Tile`/`TileGrid` 미사용).

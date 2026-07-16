# 레인지 파인더 시각화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Task 7까지 텍스트로만 보여주던 레인지 파인더 결과(방향/속도 목록)를 AR 화면에 실제로 그린다 — 계산된 궤적을 선으로, 여러 해를 구분해서, 지형 스캔 중임을 화면 중앙 마커로 표시한다.

**Architecture:** `PuttRangeFinder.verify()`가 이미 매 스텝 계산하는 공의 위치를 버리지 않고 `PuttSolution.path`에 담아 재사용한다(계산 재수행 없음). AR 렌더링은 기존 `Tile.swift`의 원통 선분 컨벤션을 따라 새 헬퍼 함수로 그리고, 기존 named-anchor 정리 패턴(`removeAnchorWithName`)으로 생명주기를 관리한다.

**Tech Stack:** Swift, simd, RealityKit(`ModelEntity`, `AnchorEntity`, `MeshResource`), ARKit, XCTest.

## Global Constraints

- 새로운 궤적/마커 시각화 코드는 물리/알고리즘 레이어(`PuttRangeFinder.swift`, ARKit 의존성 없음)와 렌더링 레이어(`ArViewContainer.swift`/`ArViewModel.swift`, ARKit 의존)를 분리한다 — 지금까지의 아키텍처 원칙을 그대로 따른다.
- 렌더링 관련 코드(Task 2, 3)는 실기기(라이다 iPhone) 없이는 완전히 검증할 수 없다 — Task 6/7과 동일하게 `xcodebuild build`로 컴파일만 확인하고 실기기 수동 확인 절차를 둔다.
- 9개 격자점 raycast 마커는 그리지 않는다 — 화면 중앙 raycast 결과 하나만 표시한다(설계 문서 2.3절, 단순함을 우선).
- 핀치 제스처로 raycast 격자 크기를 조절하는 기능은 이번 계획 범위 밖이다 — `docs/학습기록.md` 8b절 참고.
- 참고 설계 문서: `docs/superpowers/specs/2026-07-16-range-finder-visualization-design.md`

---

## Task 1: PuttSolution에 궤적(path) 추가

**Files:**
- Modify: `EasyPutt/RangeFinder/PuttRangeFinder.swift`
- Test: `EasyPuttTests/PuttRangeFinderVerifyTests.swift`

**Interfaces:**
- Consumes: 없음(기존 `PuttSolution`, `PuttRangeFinder` 내부 구조 확장).
- Produces: `PuttSolution.path: [simd_float3]`(기본값 `[]`, 기존 `PuttSolution(direction:speed:)` 호출부는 그대로 컴파일됨). `verify()`가 성공 시 반환하는 `PuttSolution`은 `path`가 채워져 있다 — 시작점(공의 실제 위치)부터 5스텝마다 기록되고, 마지막 기록은 공이 멈춘(`hasStopped`) 시점의 위치다.

- [ ] **Step 1: 실패 테스트 작성**

`EasyPuttTests/PuttRangeFinderVerifyTests.swift`의 기존 `testVerifyCorrectsADeliberatelyWrongCandidate` 아래에 추가:

```swift
    func testVerifySuccessfulCandidateIncludesPathThatReachesTheHole() {
        let terrain = makeGentleSlopeTerrain()
        let finder = PuttRangeFinder(terrain: terrain)
        let hole = simd_float3(1.5, 0, 0)
        let ball = simd_float3(-1.0, 0, 0)

        let wrongCandidate = PuttSolution(direction: simd_normalize(simd_float3(1.0, 0, 0.3)), speed: 0.5)
        let verified = finder.verify(wrongCandidate, ballPosition: ball, holePosition: hole)

        XCTAssertNotNil(verified)
        guard let verified = verified else { return }
        XCTAssertFalse(verified.path.isEmpty, "성공한 candidate는 시뮬레이션 경로를 담고 있어야 한다")

        guard let firstPoint = verified.path.first else {
            XCTFail("path가 비어있으면 안 된다")
            return
        }
        XCTAssertEqual(firstPoint.x, ball.x, accuracy: 0.01, "경로의 첫 점은 공의 실제 위치여야 한다")
        XCTAssertEqual(firstPoint.z, ball.z, accuracy: 0.01)

        let closestApproach = verified.path.map { point in
            simd_distance(simd_float3(point.x, 0, point.z), simd_float3(hole.x, 0, hole.z))
        }.min() ?? .greatestFiniteMagnitude
        XCTAssertLessThanOrEqual(
            closestApproach,
            PuttRangeFinderConfig.default.captureRadius + 0.005,
            "경로 어딘가는 홀컵의 캡처 반경 안까지 접근해야 한다"
        )
    }

    func testBackwardOnlyCandidateHasEmptyPath() {
        // verify()를 거치지 않은 순수 PuttSolution(direction:speed:)은 path가 비어있어야
        // 한다 — 기존 호출부(backwardCandidate, correct())가 컴파일과 동작 모두
        // 그대로 유지되는지 확인한다.
        let candidate = PuttSolution(direction: simd_float3(1, 0, 0), speed: 0.5)
        XCTAssertTrue(candidate.path.isEmpty)
    }
```

- [ ] **Step 2: 테스트 실행해서 실패 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests`

Expected: FAIL — `PuttSolution`에 `path` 프로퍼티가 없어서 컴파일 에러.

- [ ] **Step 3: PuttSolution, ForwardSimulationResult, simulateForward, verify 수정**

`EasyPutt/RangeFinder/PuttRangeFinder.swift`에서 `PuttSolution` 구조체를:

```swift
/// 성공(홀인 가능)으로 판정된 하나의 (방향, 속도) 조합.
struct PuttSolution {
    let direction: simd_float3 // 수평 단위벡터
    let speed: Float
    /// verify()가 성공했을 때의 정방향 시뮬레이션 경로(5스텝마다 다운샘플링, 마지막
    /// 기록은 항상 공이 멈춘 지점). 시각화 용도이며, backwardCandidate()가 만드는
    /// 근사 후보나 verify()의 중간 보정 후보에는 채워지지 않는다(빈 배열).
    let path: [simd_float3] = []
}
```

`ForwardSimulationResult`를:

```swift
    private struct ForwardSimulationResult {
        let closestPosition: simd_float3
        let closestDistance: Float
        let path: [simd_float3]
    }
```

`simulateForward`를:

```swift
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
```

`verify`를:

```swift
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
```

`PuttSolution`이 이제 3개 필드를 갖게 되므로, 위 `verify` 안의 `return PuttSolution(direction:speed:path:)` 호출은 명시적으로 3개 인자를 모두 넘긴다(memberwise init에 `path`가 기본값과 함께 포함되지만, 여기서는 명시적으로 채워야 하므로 인자를 생략하지 않는다).

**Interfaces에 명시된 대로**, `backwardCandidate`와 `correct()` 안의 기존 `PuttSolution(direction:speed:)` 2-인자 호출부는 코드 변경 없이 그대로 둔다 — `path`가 기본값 `[]`로 자동 채워진다.

- [ ] **Step 4: 테스트 실행해서 통과 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:EasyPuttTests/PuttRangeFinderVerifyTests`

Expected: PASS (4 tests: 기존 2개 + 신규 2개)

- [ ] **Step 5: 전체 스위트 회귀 확인**

Run: `xcodebuild test -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS (전체) — 특히 `PuttRangeFinderBackwardTests`, `PuttRangeFinderEndToEndTests`가 `PuttSolution`의 새 필드 때문에 깨지지 않는지 확인.

- [ ] **Step 6: 커밋**

```bash
git add EasyPutt/RangeFinder/PuttRangeFinder.swift EasyPuttTests/PuttRangeFinderVerifyTests.swift
git commit -m "PuttSolution에 verify() 성공 시의 시뮬레이션 경로(path) 추가"
```

---

## Task 2: 지형 스캔 중 화면 중앙에 raycast 마커 표시

이 태스크는 ARKit 세션이 실제로 돌아가는 실기기에서만 동작 확인 가능하다(시뮬레이터는 카메라 트래킹이 없음, README 참고). XCTest로 검증하지 않고, 마지막에 실기기 수동 확인 절차를 둔다.

**Files:**
- Modify: `EasyPutt/ArViewModel.swift`

**Interfaces:**
- Consumes: `ARViewModel.arRaycastResult`(기존, 매 틱 갱신됨), `ARViewModel.isCollectingTerrainSamples`(기존).
- Produces: `ARViewModel.updateCenterRaycastMarker()`(신규, 매 틱 호출).

- [ ] **Step 1: 마커 엔티티 프로퍼티 추가**

`EasyPutt/ArViewModel.swift`의 프로퍼티 선언부, `terrainSampleCollectionCenters` 근처에 추가:

```swift
    private var centerRaycastMarkerEntity: ModelEntity?
    private var centerRaycastMarkerAnchor: AnchorEntity?
```

- [ ] **Step 2: 마커 생성/갱신/숨김 메서드 추가**

`ArViewModel` 클래스 안, `collectTerrainSamples()` 아래에 추가:

```swift
    /// 지형 스캔 중(isCollectingTerrainSamples)에만 화면 중앙 raycast 결과(arRaycastResult)
    /// 위치에 작은 구체 마커를 표시한다. 9개 격자점 전부가 아니라 이 하나만 보여줘서
    /// "지금 지면을 인식하고 있다"는 최소한의 시각 피드백을 준다. 매 틱 새로 만들지 않고
    /// 엔티티 하나를 재사용해 위치만 갱신한다.
    func updateCenterRaycastMarker() {
        guard let arView = self.arView else { return }

        guard isCollectingTerrainSamples, let hit = arRaycastResult else {
            if let anchor = centerRaycastMarkerAnchor {
                anchor.removeFromParent()
                centerRaycastMarkerAnchor = nil
                centerRaycastMarkerEntity = nil
            }
            return
        }

        let transform = hit.worldTransform
        let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        if centerRaycastMarkerEntity == nil {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.01),
                materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
            )
            let anchor = AnchorEntity(world: .zero)
            anchor.name = "CenterRaycastMarkerAnchor"
            anchor.addChild(marker)
            arView.scene.addAnchor(anchor)
            centerRaycastMarkerEntity = marker
            centerRaycastMarkerAnchor = anchor
        }
        centerRaycastMarkerEntity?.position = position
    }
```

- [ ] **Step 3: 기존 raycast 루프에서 매 틱마다 호출**

`EasyPutt/ArViewModel.swift`의 `init()` 안, `updateSubject.throttle(...).sink { ... }` 클로저에서 `self.collectTerrainSamples()` 바로 아래에 추가:

```swift
                self.updateCenterRaycastMarker()
```

- [ ] **Step 4: 빌드 확인**

Run: `xcodebuild build -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: 실기기 수동 확인**

라이다 탑재 iPhone에서: Ball 버튼을 탭한 뒤 카메라를 홀컵 쪽으로 이동시키는 동안, 화면 중앙 지점(정확히는 그 지점이 가리키는 지면 위치)에 작은 청록색 구체가 따라다니는지 확인한다. Hole 버튼을 탭하면(스캔 종료) 마커가 사라지는지 확인한다.

- [ ] **Step 6: 커밋**

```bash
git add EasyPutt/ArViewModel.swift
git commit -m "지형 스캔 중 화면 중앙 raycast 지점에 마커 표시"
```

---

## Task 3: 궤적 선 그리기 (여러 solution 구분 표시)

이 태스크도 ARKit 실행이 필요해 실기기 수동 확인으로 검증한다.

**Files:**
- Modify: `EasyPutt/ArViewContainer.swift`

**Interfaces:**
- Consumes: Task 1의 `PuttSolution.path`, `ArViewModel.rangeFinderSolutions`(기존), `ScanPlane.swift`의 `removeAnchorWithName(for:name:)`(기존, 재사용).
- Produces: `makeTrajectorySegment(from:to:color:radius:) -> ModelEntity`(신규, 파일 하단 free function), `makeTrajectoryEntity(path:color:radius:) -> ModelEntity`(신규), `drawTrajectories(_:in:)`(신규, `Coordinator.captureHolePosition()`에서 호출).

- [ ] **Step 1: 선분/궤적 생성 헬퍼 함수 추가**

`EasyPutt/ArViewContainer.swift` 파일 맨 아래(기존 `extension ARView { func screenToWorldRay... }` 아래)에 추가:

```swift
/// 두 점을 잇는 얇은 원통 하나를 만든다 — Tile.swift의 createLineEntity와 같은
/// 컨벤션(원통 = 선)을 따르되, 화살촉/꼬리 장식은 없는 단순한 선분이다.
func makeTrajectorySegment(from start: simd_float3, to end: simd_float3, color: UIColor, radius: Float) -> ModelEntity {
    let length = simd_distance(start, end)
    guard length > 0.0001 else { return ModelEntity() }

    let direction = normalize(end - start)
    let cylinder = MeshResource.generateCylinder(height: length, radius: radius)
    let material = SimpleMaterial(color: color, isMetallic: false)
    let segmentEntity = ModelEntity(mesh: cylinder, materials: [material])
    segmentEntity.components.set(
        CollisionComponent(
            shapes: [],
            mode: .trigger,
            filter: CollisionFilter(group: CollisionGroups.displayGround, mask: [])
        )
    )
    segmentEntity.position = start + (direction * (length / 2.0))
    segmentEntity.transform.rotation = simd_quatf(from: simd_float3(0, 1, 0), to: direction)
    return segmentEntity
}

/// path의 인접한 점들을 선분으로 이어붙여 궤적 전체를 하나의 부모 엔티티로 만든다.
func makeTrajectoryEntity(path: [simd_float3], color: UIColor, radius: Float) -> ModelEntity {
    let trajectoryEntity = ModelEntity()
    guard path.count > 1 else { return trajectoryEntity }
    for index in 0..<(path.count - 1) {
        let segment = makeTrajectorySegment(from: path[index], to: path[index + 1], color: color, radius: radius)
        trajectoryEntity.addChild(segment)
    }
    return trajectoryEntity
}

/// solutions를 모두 그리되, 첫 번째(solutions[0])만 강조색/굵은 선으로, 나머지는
/// 옅은 색/얇은 선으로 그려 구분한다. 기존 "TrajectoryAnchor"가 있으면 먼저 지운다.
func drawTrajectories(_ solutions: [PuttSolution], in arView: ARView) {
    removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
    guard !solutions.isEmpty else { return }

    let anchor = AnchorEntity(world: .zero)
    anchor.name = "TrajectoryAnchor"

    for (index, solution) in solutions.enumerated() {
        let color: UIColor = index == 0 ? .systemGreen : UIColor.white.withAlphaComponent(0.4)
        let radius: Float = index == 0 ? 0.008 : 0.004
        let trajectoryEntity = makeTrajectoryEntity(path: solution.path, color: color, radius: radius)
        anchor.addChild(trajectoryEntity)
    }

    arView.scene.addAnchor(anchor)
}
```

- [ ] **Step 2: 홀컵 탭 시 궤적 그리기, 공 탭 시 이전 궤적 지우기**

`EasyPutt/ArViewContainer.swift`의 `Coordinator.captureHolePosition()`(기존)을:

```swift
        func captureHolePosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureHolePosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.holePosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.stopCollectingTerrainSamples()
            parent.arViewModel.runRangeFinder()
            if let arView = parent.arViewModel.arView {
                drawTrajectories(parent.arViewModel.rangeFinderSolutions, in: arView)
            }
        }
```

`Coordinator.captureBallPosition()`(기존)을 — 새 공 위치를 찍으면 이전 궤적은 더 이상 유효하지 않으므로 지운다:

```swift
        func captureBallPosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureBallPosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.ballPosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.startCollectingTerrainSamples()
            if let arView = parent.arViewModel.arView {
                removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
            }
        }
```

- [ ] **Step 3: 빌드 확인**

Run: `xcodebuild build -project EasyPutt.xcodeproj -scheme EasyPutt -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 실기기 수동 확인**

라이다 탑재 iPhone에서:
1. 공 위치 탭 → 카메라를 홀컵 쪽으로 이동(Task 2의 중앙 마커가 따라다님 확인) → 홀컵 위치 탭.
2. `runRangeFinder()`가 solution을 찾으면, 공에서 홀컵까지 이어지는 선(들)이 화면에 나타나는지 확인한다.
3. solution이 2개 이상이면 하나(진한 초록, 굵음)와 나머지(옅은 흰색, 얇음)가 시각적으로 구분되는지 확인한다.
4. 다시 공 위치를 탭하면 이전 궤적 선이 사라지는지 확인한다.
5. solution이 0개인 경우(평지 등) 아무 선도 안 그려지는 게 정상 동작이다.

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/ArViewContainer.swift
git commit -m "레인지 파인더 결과 궤적을 AR 화면에 선으로 표시"
```

---

## Self-Review 메모 (계획 작성자 기록용)

- **스펙 커버리지**: 설계 문서 2.1(경로 데이터)=Task 1, 2.2(궤적 렌더링+여러 해 구분)=Task 3, 2.3(중앙 마커)=Task 2 모두 커버됨. 데이터 흐름(설계 문서 3절)의 각 단계가 Task 2/3의 훅 위치와 일치하는지 확인 완료.
- **타입 일관성**: `PuttSolution`이 이제 `direction`, `speed`, `path` 3개 필드. `verify()`의 반환 경로(성공 시 3-인자 명시적 생성)와 `backwardCandidate`/`correct()`의 기존 2-인자 호출부(변경 없음, `path` 기본값 `[]`)가 서로 다른 것을 확인 — 의도된 차이.
- **Non-goals 확인**: 핀치 제스처 격자 크기 조절은 이 계획에 포함되지 않음(Global Constraints에 명시).

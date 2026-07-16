# 레인지 파인더 시각화 설계 문서

**Goal:** Task 7까지 완성된 "퍼팅 방향 레인지 파인더"의 결과(텍스트로만 표시되던 solution 목록)를 AR 화면에 실제로 그려서 보여준다. 궤적(선), 여러 해 구분, 지형 스캔 중 진행 상황 표시(마커) 세 가지를 다룬다.

**Non-goals:** 두 손가락 핀치로 레이캐스트 격자 크기를 조절하는 기능은 이번 설계에서 제외한다 — 카메라-지면 거리에 따라 화면 격자와 실제 지면 격자의 대응 관계가 달라지는(원근 투영) 문제가 있어 별도 설계가 필요하다고 판단했다. 아이디어와 핵심 통찰은 `docs/학습기록.md` 8b절에 기록해뒀다.

## 1. 배경

Task 7은 `findSolutions()`가 반환한 `[PuttSolution]`(방향+속도)을 `ContentView2.swift`에 텍스트로만 나열했다. 실제로 어느 방향으로 쳐야 하는지 화면에서 직관적으로 보려면, 계산된 궤적을 AR 공간에 선으로 그려야 한다.

## 2. 세 가지 컴포넌트

### 2.1 궤적 데이터: `PuttSolution.path`

`verify()`는 이미 각 보정 반복마다 `simulateForward()`로 공을 굴려보는데, 지금은 최종 (방향, 속도)만 남기고 매 스텝의 위치는 버린다. 이 위치들을 그대로 보존해서 재사용한다 — 계산을 다시 할 필요가 없다.

- `PuttSolution`에 `path: [simd_float3] = []` 필드를 추가한다(기본값 있는 옵셔널 성격 — 기존에 `PuttSolution(direction:speed:)`로 직접 만드는 테스트 코드들이 전부 컴파일 그대로 통과해야 하므로).
- `simulateForward()`가 매 스텝 `ball.position`을 배열에 기록해서 `ForwardSimulationResult`에 포함시킨다.
- `verify()`가 수렴에 성공한 마지막 반복의 경로를 최종 `PuttSolution.path`에 채워서 반환한다.

이 부분은 `PuttRangeFinder.swift`(순수 Swift, ARKit 의존성 없음) 안에서 끝나므로 기존처럼 XCTest로 검증 가능하다.

### 2.2 궤적 렌더링: 선분 체인 + 여러 해 구분

기존 코드베이스에는 이미 3D 선을 그리는 컨벤션이 있다 — `Tile.swift`의 `createLineEntity(from:to:color:)`가 얇은 실린더(`MeshResource.generateCylinder`) + 화살촉으로 직선 하나를 그린다. RealityKit의 `MeshDescriptor` `.lineStrip` 같은 새 API는 이 코드베이스에서 쓰인 적이 없으므로, 기존 컨벤션(직선 세그먼트를 이어붙이는 방식)을 따른다.

- `path`의 인접한 두 점마다 원통 세그먼트 하나씩 만들어서 이어붙이면 궤적 전체가 곡선처럼 보인다(스텝 간격이 촘촘하므로).
- `maxForwardSteps`(4000)가 상한이므로 극단적인 경우 세그먼트가 수천 개까지 생길 수 있다 — 렌더링 부담을 피하기 위해 일정 간격(예: 5스텝마다 1점)으로 다운샘플링해서 세그먼트 수를 줄인다. 정확한 간격은 실기기에서 성능 확인 후 튜닝한다.
- `findSolutions()`가 여러 solution을 반환하면 전부 그리되, 시각적으로 구분한다 — 하나(첫 번째 solution)는 강조 색상(예: 밝은 초록, 두꺼운 굵기)으로, 나머지는 옅은 색(예: 반투명 흰색, 얇은 굵기)으로 그린다.
- 모든 선분은 `CollisionComponent(mode: .trigger, mask: [])`로 설정해 레이캐스트/충돌에 영향을 주지 않는다(`Tile.swift`의 기존 라인 엔티티와 동일).
- 전용 `AnchorEntity`(이름: `"TrajectoryAnchor"`) 하나 아래에 모든 선분을 자식으로 추가하고 `arView.scene.addAnchor`. 새로운 홀컵 탭(`captureHolePosition()`)이 일어날 때마다 기존 `"TrajectoryAnchor"`를 `removeAnchorWithName`으로 지우고 새로 그린다(기존 `"ScullAnchor"`/`"DisplayAnchor"` 정리 패턴과 동일).

### 2.3 지형 스캔 마커: 화면 중앙 지점만 단순 표시

Task 6의 3x3 격자 raycast(`collectTerrainSamples`)는 매 틱 9개 지점을 조용히 스캔만 한다. 사용자가 공→홀컵으로 카메라를 이동시키는 동안 "지금 지면을 인식하고 있다"는 시각적 피드백이 전혀 없었다.

- 9개 격자점을 전부 표시하지 않고, **화면 중앙의 raycast 결과(`arRaycastResult`, 이미 매 틱 계산되고 있음) 하나만** 작은 구체 마커로 표시한다.
- `ScanPlane.swift`의 기존 마커 패턴(`MeshResource.generateSphere(radius: 0.01)` + `SimpleMaterial`)을 재사용한다.
- `isCollectingTerrainSamples`가 `true`인 동안에만(공 탭 이후 ~ 홀컵 탭 전까지) 표시하고, 홀컵 탭 시 사라지게 한다.
- 매 틱 위치를 업데이트해야 하므로, 마커 엔티티를 한 번만 만들고 매 틱 `.position`만 갱신하는 방식이 적절하다(매번 새로 생성/삭제하지 않음).

## 3. 데이터 흐름

```
공 탭 → captureBallPosition() → startCollectingTerrainSamples()
   ↓ (카메라를 홀컵 쪽으로 이동하는 동안, 매 틱)
   collectTerrainSamples() [기존, 9점 스캔]
   + 중앙 마커 위치 갱신 [신규, 2.3]
   ↓
홀컵 탭 → captureHolePosition() → stopCollectingTerrainSamples()
   → 중앙 마커 제거 [신규]
   → runRangeFinder() → findSolutions() [PuttSolution.path 포함, 2.1]
   → 기존 "TrajectoryAnchor" 제거 후 새로 그리기 [신규, 2.2]
   → (기존) 텍스트 결과 표시
```

## 4. 테스트 전략

- `PuttSolution.path` 채우기(2.1)는 순수 Swift 로직이라 XCTest로 검증한다 — 예: `verify()`가 성공했을 때 `path`가 비어있지 않고, 마지막 점이 `captureRadius` 이내에 있는지.
- 렌더링(2.2, 2.3)은 Task 6/7과 동일하게 ARKit 의존적이라 `xcodebuild build`로 컴파일만 확인하고, 실기기 수동 검증이 필요하다.

## 5. 변경 파일 예상 범위

- `EasyPutt/RangeFinder/PuttRangeFinder.swift` — `PuttSolution.path` 추가, `simulateForward`/`verify` 수정
- `EasyPutt/ArViewModel.swift` — 중앙 마커 엔티티 관리, 궤적 그리기 트리거
- `EasyPutt/ArViewContainer.swift` — 궤적 선분 생성 헬퍼(또는 `Tile.swift`의 `createLineEntity` 재사용/이동 검토)
- `EasyPuttTests/PuttRangeFinderVerifyTests.swift` 또는 `EndToEndTests` — path 채워짐 검증 테스트 추가

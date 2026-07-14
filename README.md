# EasyPutt

ARKit + RealityKit 기반 골프 퍼팅 그린 스캔 & 퍼팅 시뮬레이터 iOS 앱.

카메라로 실제 퍼팅 그린(또는 임의의 바닥면)을 스캔해서 굴곡(경사)을 타일 단위로
측정하고, 그 위에 실물 규격에 가까운 골프공을 올려 실제 경사를 반영한 구름
물리 시뮬레이션으로 퍼팅 궤적을 확인하는 프로젝트입니다.

## 동작 방식

1. **Start** — 화면 중앙의 리티클(FocusEntity)이 감지한 바닥 위치에 시작점
   마커(`scull` 모델)를 찍습니다.
2. **End** — 도착점 위치에 두 번째 마커를 찍습니다. 시작점→도착점 벡터를
   기준으로 그 사이 영역을 삼각분할된 타일 그리드로 생성합니다
   (`TileGrid.generateTiles()`).
3. **Scan** (누르고 있기/탭) — 그리드의 각 타일 모서리 점에서 아래 방향으로
   `ARRaycastQuery`를 쏴서 실제 바닥면의 높이·법선(normal)을 측정하고,
   측정된 높이로 보정된 "projected tile"을 만듭니다. 즉 화면에 보이는 평평한
   가상 그리드가 아니라 실제 바닥의 굴곡을 그대로 반영한 타일이 만들어집니다.
4. **Smth** (Smooth) — 스캔 중 raycast 노이즈로 튀는 높이값을
   `makeSmoothTile()` / `makeSmoothPadding()`으로 보간·평활화해서
   `smoothedProjectedTile`을 생성합니다.
5. **탭(Tap)** — 스캔된 그리드 위 아무 지점을 탭하면 그 자리에 실물 규격
   골프공(반지름 21.35mm, 질량 45.93g)이 스폰됩니다. 상단 슬라이더의
   `Speed`(속도)와 `Direction`(도착점 기준 좌우 편향/조준)값으로 초기 속도
   벡터를 계산해 공을 굴립니다.
6. 공은 매 프레임 자신이 위치한 타일을 찾아 그 타일의 실측 법선 벡터를
   가져와 `GolfBall.updateFromTorque(deltaTime:surfaceNormal:)`로 굴림
   물리를 갱신합니다 — 즉 스캔한 실제 그린의 경사를 그대로 타고 굴러갑니다.
   공이 멈추거나(`hasStopped`) 그리드 밖으로 나가면 시뮬레이션이 종료됩니다.
7. **Reset** — 앵커/마커/그리드를 전부 지우고 처음부터 다시 스캔할 수
   있도록 초기화합니다.

## 골프공 물리 모델 (`GolfBall.swift`)

- 반지름 0.021m, 질량 0.045kg — 실제 골프공 스펙에 가깝게 설정.
- 중력을 접촉면 법선(surface normal) 방향과 접선 방향으로 분해해서,
  접선 방향 성분만으로 가속도를 계산 (구슬이 경사면을 굴러 내려가는
  방식과 동일한 원리, 가속도 계수 5/7은 균일 구체의 구름 관성 계수).
- `update(deltaTime:surfaceNormal:)` — 단순 "미끄러짐 없는 구름" 가정 버전.
- `updateFromTorque(deltaTime:surfaceNormal:)` — 마찰력 → 토크 → 각가속도로
  이어지는 좀 더 물리적인 버전. 정지마찰계수(0.4)/운동마찰계수(0.2)를 두고
  각속도가 목표 각속도에 수렴하면 "구름 상태(rolling)"로 판정.
- 실제 탭-투-퍼팅 흐름에서 쓰이는 마찰/반발 값은 `ArViewContainer.swift`의
  `handleTap`에서 별도로 `PhysicsMaterialResource`(staticFriction 0.1,
  dynamicFriction 0.04, restitution 0.0)로도 설정됨.

## 타일 그리드 (`Tile.swift`, `TileGrid.swift`)

- 각 사각형 셀을 대각선으로 나눠 "up 삼각형"/"down 삼각형" 두 개로 취급하고,
  무게중심 좌표(barycentric weight, `solveWeights`)로 공이 어느 삼각형 위에
  있는지(`isOnTheTile`) 판정합니다 — 삼각형 단위로 법선을 따로 가지므로
  같은 타일 안에서도 대각선 방향 굴곡을 반영할 수 있습니다.
- `scanTile`, `makePadding`/`makeSmoothPadding` — 타일 사이 이음매(패딩)를
  채워 넣어 이웃 타일과 자연스럽게 이어지는 스캔 메시를 만듭니다.
- 현재 `ArViewModel.getTileHeight()`는 상하좌우 인접 타일 이동만 처리하고
  대각선 이동은 처리하지 않습니다 (`나중에 대각선 움직임 반영` 주석 참고,
  미구현 상태).

## 프로젝트 구조

```
EasyPutt/
├── EasyPuttApp.swift          # @main AppDelegate, UIHostingController(ContentView2) 진입점
├── ContentView2.swift         # 실제 사용 중인 메인 화면 (AR 배경 + 슬라이더 + 버튼 툴바)
├── ContentView.swift          # 이전/대안 구현 (ARViewControllerRepresentable 기반, 현재 미사용)
├── ArViewContainer.swift      # UIViewRepresentable ARView 래퍼: 세션 델리게이트, 탭 제스처(퍼팅 스폰),
│                               #   ARCoachingOverlay, FocusEntity 트래킹
├── ArViewModel.swift          # ObservableObject: raycast 처리, 스캔 파이프라인, 충돌 이벤트,
│                               #   타일 높이 전이(getTileHeight) 로직
├── TileGrid.swift             # 시작점/도착점 사이 타일 그리드 생성·스캔·평활화·표시
├── Tile.swift                 # 개별 타일: 삼각형 판정, projected/smoothed 엔티티 생성, 패딩
├── GolfBall.swift             # 골프공 구름 물리 모델 + SwiftUI 프리뷰용 GolfBallView
├── ScanPlane.swift            # 모델 로드/배치, 앵커 제거, start/end 셋업, raycast 유틸리티
├── CollisionGroup.swift       # RealityKit CollisionGroup 정의 (타일/공/화살표/바닥)
├── MiscMath.swift             # 3D 보간, LiDAR 깊이 기반 월드 좌표 변환 등 수학 유틸리티
├── FocusEntity/                # AR 리티클(조준 표시) 라이브러리 — 로컬 소스로 편입 (아래 참고)
├── Resources/                 # 3D 모델(scull.usdz 등), 이미지 에셋
└── Preview Content/            # SwiftUI 프리뷰 전용 에셋
```

## 의존성

- **FocusEntity** — 원래 `github.com/maxxfrazer/FocusEntity` SPM 패키지로
  받아 쓰고 있었는데, 최신 Xcode SDK가 그 패키지 내부의
  `import RealityFoundation`을 "RealityKit의 비공개 구현 모듈"이라는 이유로
  막아버려서 빌드가 깨졌습니다. SPM 의존성을 제거하고, 이미 로컬에 있던
  FocusEntity 소스(`EasyPutt/FocusEntity/`)를 프로젝트에 직접 편입해서
  해당 import만 제거하는 방식으로 해결했습니다. 즉 이 폴더는 서드파티
  코드지만 외부 패키지가 아니라 리포에 포함된 로컬 소스입니다.
- 그 외 외부 의존성 없음 (Apple 프레임워크: ARKit, RealityKit, SwiftUI,
  Combine, simd만 사용).

## 요구 사항

- **실기기 전용** — `UIRequiredDeviceCapabilities = arkit`,
  `NSCameraUsageDescription` 설정돼 있어 시뮬레이터로는 실행할 수 없습니다
  (카메라 트래킹이 필요).
- iOS 18.2 이상 (`IPHONEOS_DEPLOYMENT_TARGET`).
- Xcode 16.2 이상.

## 빌드

```bash
open EasyPutt.xcodeproj
```

또는 CLI로:

```bash
xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt \
  -destination "generic/platform=iOS" build
```

실기기에 설치해서 테스트하려면 `-destination "id=<DEVICE_ID>"`로 바꾸고
서명이 되어 있어야 합니다 (`DEVELOPMENT_TEAM` 자동 서명 설정됨).

## 알려진 미구현/제한 사항

- 공이 타일 그리드를 대각선으로 이동하는 경우 높이 전이 처리가 안 돼
  있습니다 (`ArViewModel.getTileHeight()` 참고).
- `test.txt`는 스캔/충돌 판정 디버깅 중 남은 콘솔 로그 덤프 파일로,
  프로젝트 동작에는 사용되지 않습니다.

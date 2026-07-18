# EasyPutt

ARKit + RealityKit 기반 골프 퍼팅 레인지파인더 iOS 앱.

카메라로 실제 그린(또는 임의의 바닥면)의 볼→홀 사이 지형을 스캔해서 법선벡터를
수집하고, 그 지형 데이터를 바탕으로 "어느 방향으로, 얼마의 세기로 쳐야 홀에
들어가는지"를 계산해 AR 화면 위에 조준 방향·궤적선으로 보여주는 프로젝트입니다.

## 동작 방식

1. 화면 하단 **+** 버튼을 누르면 화면 중앙(조준 리티클)이 가리키는 지점이
   **볼 위치**로 캡처됩니다. 이 순간부터 지형 스캔이 시작됩니다.
2. 볼→홀 사이를 카메라로 훑으면, 화면 중앙의 3x3 격자(핀치로 칸 크기 조절
   가능)가 가리키는 9개 지점의 (좌표, 법선벡터)가 계속 수집됩니다
   (`ArViewModel.collectTerrainSamples()`).
3. **+** 버튼을 다시 누르면 그 지점이 **홀 위치**로 캡처되고 스캔이 멈춘 뒤,
   수집된 지형 데이터로 레인지파인더 계산이 실행됩니다
   (`ArViewModel.runRangeFinder()`).
4. 계산은 서로 독립된 **두 가지 방식**으로 동시에 수행되고 화면에 같이
   표시됩니다 — 값과 소요시간을 비교할 수 있습니다.
   - **백+포워드**: 홀에서 볼 쪽으로 거슬러 올라가는 백워드 추적으로 초기
     후보를 구하고, 그 후보를 볼에서 다시 정방향으로 시뮬레이션해서 홀과의
     오차를 반복 보정합니다(`verify`/`correct`). 좌우 조준 여유 범위도
     forward 시뮬레이션으로 직접 검증합니다(`directionRange`). 빨강/초록
     궤적선.
   - **백워드 전용**: forward 시뮬레이션(반복 보정) 없이, 홀에서부터 여러
     각도로 백워드 추적만 반복하며 이분탐색으로 볼 위치에 정확히 도달하는
     각도를 직접 찾습니다. 마지막에 딱 한 번 forward 시뮬레이션으로
     "실제로 홀에 들어가는지"만 확인합니다. 계산이 훨씬 빠른 대신 근사치.
     파랑/주황 궤적선.
5. 조준 방향은 "홀컵 기준 왼쪽/오른쪽 몇 cm를 보고 쳐야 하는지"로도 함께
   표시됩니다(`ArViewModel.puttRelative`/`aimOffsetCentimeters`) — 볼에 서서
   홀을 바라보는 시점 기준입니다.
6. 상단 **Stimpmeter** +/- 로 그린 스피드(구름저항)를 조절할 수 있고, 이에
   따라 실제 거리와 "평지였다면 몇 m짜리 퍼트였을지"(평지환산 거리)를 같이
   보여줍니다.
7. **화면 확대**(+/- , 1.0~3.0배 디지털 줌)와 **스냅샷**(사진 앱 저장) 버튼이
   있습니다.
8. **결과**/**법선** 버튼으로 계산 결과 패널/수집된 지형 샘플 목록을 각각
   토글해서 볼 수 있습니다.
9. **Reset**으로 볼/홀 위치, 계산 결과, 수집된 지형 데이터, AR 마커를 전부
   지우고 처음부터 다시 시작할 수 있습니다.

## 핵심 물리 모델

### 골프공 (`GolfBall.swift`)

- 반지름 0.021m, 질량 0.045kg — 실제 골프공 스펙.
- `updateFromTorque(deltaTime:surfaceNormal:)` — 마찰력 → 토크 → 각가속도로
  이어지는 구름 물리. `deltaTime`이 음수면 정방향 스텝의 정확한 시간역행(백워드
  추적)으로 동작합니다.
- `rollingResistance`(구름저항 감속 계수)는 스팀프미터 값에서 환산됩니다:
  `rollingResistance = releaseSpeed² / (2 × stimpReading)`.

### 레인지파인더 (`RangeFinder/PuttRangeFinder.swift`, `TerrainSampleStore.swift`)

- `TerrainSampleStore` — 수집한 (좌표, 법선) 원시 샘플 리스트. 질의 지점에
  가장 가까운 샘플을 **수평(X,Z) 거리 기준**(높이 차이는 무시)으로 찾아
  반환합니다.
- `captureRadius`(홀인 판정 허용 오차) = **홀 반경(5.4cm) 그 자체**입니다.
  공 전체가 완전히 홀 위에 떠야 캡처된다고 보는 게 아니라, 공의 무게중심이
  홀 반경 안(허공 위)으로 들어오는 순간 중력에 지지를 잃고 떨어진다는
  물리에 근거합니다.
- 캡처/도달 판정은 매 시뮬레이션 스텝 끝점만 보지 않고, 직전~다음 위치를
  잇는 **선분과 목표 지점 사이의 최소 거리**로 판정합니다(빠른 공이 좁은
  반경을 한 스텝 만에 지나쳐버리는 걸 방지).

## 프로젝트 구조

```
EasyPutt/
├── EasyPuttApp.swift            # @main AppDelegate, UIHostingController(ContentView2) 진입점
├── ContentView2.swift           # 실제 사용 중인 메인 화면 (AR 배경 + 상단 컨트롤 + 결과 패널 + 하단 바)
├── ContentView.swift            # 이전 구현 잔재, 현재 미사용
├── ArViewContainer.swift        # UIViewRepresentable ARView 래퍼: 세션 델리게이트, AR 마커(공/깃발/궤적선) 렌더링
├── ArViewModel.swift            # ObservableObject: raycast, 지형 스캔 파이프라인, 스팀프미터/줌/스냅샷, 레인지파인더 호출
├── RangeFinder/
│   ├── PuttRangeFinder.swift    # 핵심 알고리즘 — 백+포워드/백워드 전용 두 솔버, 좌우 조준 범위 계산
│   └── TerrainSampleStore.swift # 수집된 (좌표, 법선) 샘플 저장/최근접 조회
├── GolfBall.swift               # 골프공 구름 물리 모델
├── ScanPlane.swift              # 모델 로드/배치, 앵커 제거, raycast 유틸리티
├── CollisionGroup.swift         # RealityKit CollisionGroup 정의
├── MiscMath.swift               # 3D 보간 등 수학 유틸리티
├── FocusEntity/                 # AR 리티클(조준 표시) 라이브러리 — 로컬 소스로 편입 (아래 참고)
├── Resources/                   # 3D 모델, 이미지 에셋
└── Preview Content/             # SwiftUI 프리뷰 전용 에셋

EasyPuttTests/
├── PuttRangeFinderBackwardTests.swift    # 백워드 추적 후보 계산 테스트
├── PuttRangeFinderVerifyTests.swift      # forward 검증/보정 루프 테스트
├── PuttRangeFinderEndToEndTests.swift    # findSolutions 전체 파이프라인 테스트
├── TerrainSampleStoreTests.swift         # 최근접 샘플 조회 테스트
└── GolfBallRollingResistanceTests.swift  # 구름저항 물리 테스트
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
  (카메라 트래킹이 필요). 테스트(XCTest)는 시뮬레이터에서도 돌아갑니다.
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

테스트 실행:

```bash
xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt \
  -destination "platform=iOS Simulator,name=iPhone 16" test
```

## 알려진 미구현/제한 사항

- 백워드 전용 솔버는 홀→볼 직선 기준 ±60도 범위 안에서만 각도를 탐색합니다
  — 그 범위를 벗어나는 극단적인 브레이크가 필요한 지형에서는 해를 못 찾을
  수 있습니다.
- 지형 샘플은 사용자가 볼→홀 사이를 카메라로 훑은 경로 주변에서만
  수집되므로, 그 좁은 회랑을 크게 벗어나는 각도를 탐색하면 멀리 떨어진(덜
  대표성 있는) 샘플의 법선벡터를 그대로 갖다 쓰게 됩니다.
- 슬라이딩 마찰 → 구름 전환 구간의 병진 감속(토크로 인한 병진 속도 손실)은
  단순화되어 있습니다.

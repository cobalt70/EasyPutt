# EasyPutt

ARKit + RealityKit 기반 골프 퍼팅 레인지파인더 iOS 앱.

카메라로 실제 그린(또는 임의의 바닥면)의 볼→홀 사이 지형을 스캔해서 법선벡터를
수집하고, 그 지형 데이터를 바탕으로 "어느 방향으로, 얼마의 세기로 쳐야 홀에
들어가는지"를 계산해 AR 화면 위에 조준 방향·궤적선으로 보여주는 프로젝트입니다.

## 동작 방식

1. 화면 하단 **+** 버튼을 누르면 화면 중앙(조준 리티클 — 지면 트래킹 상태에
   따라 초록/노랑/파랑으로 바뀌는, 투명 배경 위 "+" 모양)이 가리키는 지점이
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
6. 계산이 끝나면 화면 상단에 **결과 카드**가 뜹니다 — 조준범위(홀 반경/공
   크기 기준 컵 단위 문구), 실제 거리, "평지였다면 몇 m짜리 퍼트였을지"
   (평지환산 거리) 세 줄. 카드를 탭하면 조준범위 한 줄로 접히고, 다시
   탭하면 펼쳐집니다.
7. 화면 **우측 상단 코너**에서 핀치하면 **화면 확대**(1.0~3.0배 디지털 줌)
   슬라이더가 나타나고, 손을 떼면 잠시 후 자동으로 사라집니다. 그 아래
   카메라 아이콘으로 **스냅샷**을 사진 앱에 저장합니다.
8. 하단 **설정** 버튼을 누르면 **Stimpmeter**(그린 스피드/구름저항) 조절과,
   두 솔버(백+포워드/백워드 전용) 계산 결과를 자세히 비교하는 **고급**
   섹션이 담긴 시트가 뜹니다.
9. **Reset**으로 볼/홀 위치, 계산 결과, 수집된 지형 데이터, AR 마커를 전부
   지우고 처음부터 다시 시작할 수 있습니다.

## 핵심 물리 모델

### 골프공 (`GolfBall.swift`)

- 반지름 0.021m, 질량 0.045kg — 실제 골프공 스펙.
- `updateFromTorque(deltaTime:surfaceNormal:)` — 마찰력 → 토크 → 각가속도로
  이어지는 구름 물리. `deltaTime`이 음수면 정방향 스텝의 시간역행(백워드
  추적)으로 동작합니다.
- `rollingResistance`(구름저항 감속 계수)는 스팀프미터 값에서 환산됩니다:
  `rollingResistance = releaseSpeed² / (2 × stimpReading)`.

#### 매 스텝에 작용하는 두 가지 힘

1. **경사 가속도** — 중력을 그 지점 법선벡터(`surfaceNormal`)에 수직인
   방향(경사면 위 방향)으로 투영한 성분 `gravityParallel`에서 나옵니다.
   `acceleration = normalize(gravityParallel) × |gravityParallel| × (5/7)`
   (5/7은 균일한 구체가 미끄러짐 없이 구를 때의 관성 계수). 평지면 0,
   경사가 있으면 그 방향으로 속도벡터의 **방향과 크기**를 둘 다 바꿉니다.
2. **구름저항** — `rollingResistance`만큼 속력을 매 스텝 일정하게 깎는
   감속(`applyRollingResistance`). 방향은 그대로 두고 크기만 줄입니다.
   물리적인 마찰계수(μ)라기보다, 스팀프미터 실측 거리로 캘리브레이션된
   "이 그린에서 관측되는 감속 정도"입니다.

#### 정방향(forward)과 역방향(backward) 적분이 서로 다른 이유

- **정방향(dt≥0)** — 진입 시점 속도 `v`를 기준으로 정확한 운동학 공식을
  씁니다: `position += v·dt + 0.5·a·dt²`, 그 다음 `velocity += a·dt`,
  구름저항 적용. 한 스텝 안의 곡률(경사 가속도로 인한 방향 전환)까지
  반영한 더 정밀한 근사입니다.
- **역방향(dt<0)** — `0.5·a·dt²` 보정 없이 `position += velocity·dt`만
  쓰고, 서브스텝 순서를 정방향과 정확히 뒤집습니다(정방향은
  가속→마찰→위치 순, 역방향은 위치→마찰 되돌리기→가속 되돌리기 순).
  이러면 각 연산이 개별적으로 역연산 가능하기만 하면 "순서를 통째로
  뒤집는 것만으로" 전체 스텝의 정확한 역연산이 보장됩니다 —
  `0.5·a·dt²` 항까지 넣으면 이 역연산 관계를 처음부터 다시 증명해야
  해서(특히 구름저항이 단순 상수 가속도가 아니라 비선형 감속이라)
  일부러 더 단순한 이 방식을 유지합니다.
- 정방향이 역방향의 "정확한 역연산일 필요"는 더 이상 없습니다 — 백워드
  추적이 만든 후보는 이제 항상 forward 시뮬레이션(`verify`/`correct`,
  또는 백워드 전용의 1회성 forward 검증)으로 독립적으로 다시 확인되기
  때문입니다. 그래서 정방향만 더 정밀한 공식으로 바꿔도 안전합니다.

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
├── EasyPuttApp.swift            # @main AppDelegate, UIHostingController(ContentView) 진입점
├── ContentView.swift            # 메인 화면 (AR 배경 + 상단 결과 카드 + 우측 상단 줌/스냅샷 + 하단 바 + 설정 시트)
├── ArViewContainer.swift        # UIViewRepresentable ARView 래퍼: 세션 델리게이트, AR 마커(공/깃발/궤적선) 렌더링
├── ArViewModel.swift            # ObservableObject: raycast, 지형 스캔 파이프라인, 스팀프미터/줌/스냅샷, 레인지파인더 호출
├── AimDescription.swift         # 조준 오프셋(cm) → 컵 단위 문구 변환 (순수 함수)
├── SymbolTexture.swift          # SF Symbol → 투명 배경 텍스처 렌더링 (FocusEntity "+" 리티클용)
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
├── GolfBallRollingResistanceTests.swift  # 구름저항 물리 테스트
└── AimDescriptionTests.swift             # 컵 단위 문구 변환 경계값 테스트
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
  (카메라 트래킹이 필요). **XCTest도 마찬가지로 시뮬레이터에서 돌릴 수
  없습니다** — 유닛 테스트가 앱 자체를 테스트 호스트로 띄우는 방식인데,
  그 앱이 ARKit capability 때문에 시뮬레이터에서 launch조차 안 되기
  때문입니다(`xcodebuild test`는 실기기 destination에서만 성공합니다).
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

테스트 실행 (실기기 destination 필요 — 위 참고):

```bash
xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt \
  -destination "id=<DEVICE_ID>" test
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

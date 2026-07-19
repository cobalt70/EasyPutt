# PuttPro 기능 분석

> 분석 대상: https://github.com/cobalt70/PuttPro.git (clone 시점 최신 main, HEAD `478f77e`)
> 분석 방법: 저장소를 스크래치패드(`/private/tmp/.../scratchpad/PuttPro`)에 클론해 소스 전체(Swift 약 7,700줄)를 직접 읽고 정리. 저장소 자체는 임시 클론이라 이 문서 외에는 남기지 않음.

## 1. 정체 — EasyPutt의 이전 세대 프로토타입

`git log`와 코드 내 헤더 주석을 보면 프로젝트명이 **TangTong → TingTing/TingPutt → PuttPro**로 여러 차례 바뀌었고, 클래스 대부분의 헤더 주석에는 여전히 `TangTong`/`TingTing`이 남아있다. 로컬라이제이션 문자열(`help_title = "📘EasyPutt User Guide"`), 구독 그룹 이름(`EasyPuttPremium`), 상품 ID(`giwoo.easyputt.yearly`)는 전부 **"EasyPutt"** 브랜드를 쓰고 있어, 현재 작업 중인 `EasyPutt` 프로젝트와 사실상 같은 제품의 **이전 세대 구현체(iOS, ARKit+RealityKit)** 다. 즉 완전히 다른 앱이 아니라, 같은 아이디어를 먼저 실험했던 코드베이스로 보는 게 맞다.

- 언어/프레임워크: Swift, ARKit(world tracking, scene depth), RealityKit(엔티티/충돌/물리), StoreKit 2(구독)
- 최소 요구: LiDAR 없는 기기 대응 코드 있음(`supportsFrameSemantics(.sceneDepth)` 체크), iOS 18 가용성 분기(`#available(iOS 18.0, *)`) 다수
- 앱 진입점: `AppDelegate`(SwiftUI 대신 UIKit `@main`), `ContentView`가 탭 없이 `selectedTab`(0=측정, 1=시뮬레이션)으로 화면 전환

## 2. 핵심 아이디어: "타일 그리드로 그린 전체를 메쉬로 재구성"

EasyPutt(현재 프로젝트)이 볼→홀 경로를 따라 카메라로 훑은 좁은 회랑에서 (좌표, 법선) **점 샘플**만 듬성듬성 모으는 방식인 것과 달리, PuttPro는 볼-홀을 잇는 직사각형 영역 전체를 **격자(Tile) 메쉬**로 만들어 각 타일의 네 꼭짓점을 개별적으로 raycast해서 지형을 통째로 재구성한다.

### 2.1 TileGrid / Tile (`TileGrid.swift` 1,342줄, `Tile.swift` 1,041줄)

1. `markStart()` / `targetEnd()`로 볼/홀 두 지점을 찍으면 `TileGrid`가 두 점을 잇는 로컬 좌표계(전방/측면 단위벡터, `worldToLocalMatrix`/`localToWorldMatrix`)를 만든다.
2. 거리에 따라 행(row) 개수를 계산하고, 열(col)은 3열(좁게) 또는 5열(`isWideMode` 토글, "Wide" 스위치로 유저가 켤 수 있음)로 고정 폭 타일(기본 0.30m × 0.30m, padding 0.02m)을 촘촘히 배치한다.
3. **원본 타일(`tiles`)** → 화면 중앙 raycast로 각 타일을 순서대로 스캔(`scanTile`/`batchProjectTiles`, 롱프레스+드래그 제스처로 트리거) → 네 꼭짓점이 모두 raycast에 성공하면 **투영 타일(`projectedTiles`)** 로 승격.
4. 각 사각 타일은 대각선으로 쪼갠 **삼각형 2개**(up/down triangle)로 취급되고, 삼각형마다 법선벡터를 외적으로 계산해 저장(`projectedUpNormal`/`projectedDnNormal`).
5. 타일 사이 이음매(패딩) 처리: `makeRightPadding`/`makeUpPadding`/`makeJunctionPadding`으로 인접 타일 경계에 별도의 얇은 보정 메쉬를 끼워 넣어 "타일과 타일 사이 빈틈"에서도 위치 판정이 되게 함. 이후 `makeSmoothTile()`로 인접 타일 꼭짓점 4~ 개를 평균 내는 스무딩까지 별도로 수행(원본/투영/스무딩 3벌의 데이터를 각각 들고 다님).
6. `isOnTheTile(situatedAt:)` — barycentric 좌표(2×2 선형계 풀이, `solveWeights`)로 어떤 점이 어느 타일의 어느 삼각형 위에 있는지 판정. 메인 타일 → 오른쪽 패딩 → 이음매 패딩 → 위쪽 패딩 순서로 4번 시도.

이 방식은 그린 표면을 실제로 "면"으로 재구성하기 때문에 임의 지점의 법선을 촘촘하게 알 수 있다는 장점이 있지만, 스캔 UX 비용(타일 수만큼 raycast, 실패 시 재시도 안내)과 코드 복잡도(원본/투영/스무딩 3중 좌표 배열, 패딩 로직)가 크다.

### 2.2 실시간 갱신 루프

`ARViewModel.init()`에서 0.1초 throttle로 화면 중앙 raycast를 계속 돌리며(`updateSubject`), 스캔 모드(`isScanning`)일 때 화면에 보이는(`isPointsVisible`) 미투영 타일을 찾아 그 자리에서 4점을 다시 raycast하는 **보조 스캔 루프**가 별도로 존재한다 — 즉 롱프레스 배치 스캔과 프레임별 보조 스캔 두 경로가 같은 일을 한다(코드 중복, 주석에도 "필요한건지 다시 한번 고민" 등 저자 스스로의 의문이 남아있음).

## 3. 물리 / 경로 탐색

### 3.1 공 물리 모델 (`GolfBall.swift`)

- 반지름 0.022m, 질량 0.045kg. 두 가지 업데이트 함수:
  - `update(deltaTime:surfaceNormal:)` — 토크 없이 마찰만으로 단순화한 구름(레거시로 보임, 미사용 경로 존재).
  - `updateFromTorque(deltaTime:surfaceNormal:)` — **슬라이딩 → 순수 구름 전이**를 명시적으로 모델링. 마찰력→토크→각가속도 누적, 목표 각속도(`v/r`)와 현재 각속도 차이가 임계각 이하가 되면 "Pure Rolling" 상태로 전환하고, 이후엔 각속도를 선속도에 강제로 연동시킴. 전이 시점 이후엔 `reduceFactor(0.7)`를 곱한 감쇠 마찰을 적용.

### 3.2 방향/속도 탐색 (`FindPath.swift`, 686줄) — 이 프로젝트의 핵심 알고리즘

EasyPutt의 "백워드 추적 + forward 보정"과 달리, PuttPro는 **완전 탐색(brute-force sweep)** 방식이다.

1. `calcMinMaxVelocity()` — 볼-홀 경사각(α)과 유효 감속(경사성분 + 마�찰성분)으로부터 시도할 속도 범위 `[minVelocity, maxVelocity]`와 스텝 크기를 규칙 기반으로 정한다(오르막/내리막 정도에 따라 8단계 분기, 감속이 0 이하이거나 매우 작은 임계 상황을 별도 처리).
2. `scanVelocityRange()` — 그 범위를 `velocityStep`(기본 0.05, 급경사 내리막은 0.025) 간격으로 훑으며 각 속도마다 `adaptiveDirectionSearch()` 호출.
3. `adaptiveDirectionSearch()` — 홀 방향을 중심으로 좌우 오프셋 인덱스(±63, 0.025m 간격 = 최대 약 ±1.6m)를 `[0,-1,1,-2,2,...]` 순서로 훑으며, 각 방향에 대해 **RK4(4차 룽게-쿠타) 적분**으로 실제 궤적을 시뮬레이션(`rungeKuttaSimulate`)해 홀을 통과하는지 확인. 통과 성공/실패 경계를 찾으면 그 방향에서 더 이상 탐색하지 않도록 조기 종료.
4. `rungeKuttaSimulate()` — 매 스텝 `tileGrid.normalVector(at:)`로 현재 위치의 지형 법선을 조회해 경사 가속도 + 마찰(슬라이딩→구름 전이 포함)을 계산, RK4로 위치/속도 갱신. 시간 스텝은 속도에 반비례하게 가변(`desiredStepDistance/v`, 0.01~1.0초로 클램프)해서 빠른 공이 홀을 건너뛰는 걸 막는다. 홀 반경 + 여유(`radiusExt`) 안에 들어오면 성공 처리. 거리가 계속 멀어지고 속도가 빨라지거나 느려지는 패턴을 감지하면 조기 종료(`shouldTerminate`).
5. 여러 속도 중 **가장 넓은 방향 범위(min~max index)를 만든 속도**를 최종 추천 속도로 채택하고, 그 최소/최대 방향의 궤적을 빨강/파랑 구슬 줄로 화면에 표시.

즉 EasyPutt이 "역방향 적분으로 후보를 빠르게 좁히고 정방향으로 검증"하는 것과 달리, PuttPro는 애초에 **속도×방향 2차원 그리드를 전부 정방향 RK4로 시뮬레이션**해서 성공 영역의 경계를 찾는다. 정확도는 높을 수 있으나(각 지점마다 실측 법선을 쓰므로) 연산량이 훨씬 많고(초당 여러 번의 중첩 루프 + RK4), `distanceDirect > 1.5m`일 때 구독 유도 로직이 주석 처리되어 있는 것으로 보아 실기기 성능/과금 정책과 씨름한 흔적이 보인다.

### 3.3 별도의 해석적 AimPoint 공식 (`InterpretTiles.swift`)

RK4 탐색과 별개로, 화면 상단에 즉시 보여주는 "몇 컵 아웃" 표시는 EasyPutt과 유사한 **단순 해석식**을 그대로 쓴다:

```
aimInMeters = |K0 · sin(theta) · sin(alpha) · stimp · distance²|
```

- `alpha`: 그린 중앙 열(centerCol)의 위/아래 삼각형 법선을 모두 평균한 **평면 전체의 경사각**(워터폴 방향의 강도)
- `theta`: 볼→홀 진행 방향과 워터폴 방향 사이의 각도(시계 방향, atan2로 0~360°)
- `constK = 0.9`
- `stimp`: 유저가 슬라이더로 입력한 스팀프미터(1.8~4.0m)

이 값은 RK4 탐색 결과(min/max index)와는 **독립적으로** 계산되어 화면 오버레이(`GreenReadingOverlayView`)에 별도로 표시된다 — 정밀 탐색(RK4)과 즉석 근사(해석식)를 동시에 보여주는 이중 트랙 구조. 사용자 메모리에 있는 "분석적 접근 선호"(`feedback_prefer_analytic_over_iterative`) 원칙과 맥이 닿는 설계다.

### 3.4 마찰 계수 산출

```swift
muRolling = |-(1.83)² / (2 · stimp)| / 9.81
muKinetic = muRolling × kineticRatio(stimp)   // stimp 구간별 2.0~2.4배
```
1.83 m/s는 스팀프미터 표준 릴리즈 속도(6ft 경사대 기준 실측 상수)로 보인다. `kineticRatio`는 그린이 빠를수록(스팀프가 클수록) 슬라이딩 구간 마찰 비율을 낮게 잡는 보정 테이블.

## 4. UI / UX 구성

| 화면 | 파일 | 역할 |
|---|---|---|
| 측정 탭 | `MeasureView.swift` | 하단 Reset/Mark(+)/Scan(grid) 버튼. Mark는 탭, Scan은 **롱프레스+드래그**로 스캔 실행 — 제스처가 꽤 복합적(단순 탭/롱프레스/드래그 3종 동시 인식) |
| 결과 오버레이 | `GreenReadView.swift`, `GreenReadingOverlayView.swift` | 조준 범위("Left 1¼ cups" 등 컵 단위 서술), 거리/경사보정거리, 스팀프미터, Wide 토글 |
| 시뮬레이션 탭 | `SimulationView.swift` | AimRuler + 스팀프 슬라이더 + 방향패드(좌우 1° 단위, 최대 ±42) + 속도 챈버 + Shoot 버튼으로 실제 공을 굴려서 눈으로 검증 |
| 조준 눈금자 | `AimRuler.swift` | 가로 눈금 84개(±42)로 좌우 조준 오프셋을 시각화, 방향 인덱스가 그대로 눈금 위치가 됨 |
| 워터폴 표시 | `WaterFallView.swift`, `showWaterFall()` | 경사 강도에 따라 화살표 길이(6~12cm)를 4단계로 다르게 그림 |
| 거리선 | `LineConnector.swift` | 볼-홀 사이 점선 + 3D 텍스트 라벨(거리는 카메라 방향으로 look-at) |
| 스팀프미터 입력 | `StimpMeterView.swift`(슬라이더), `StimpMeterSheetView.swift`(휠 피커) | 두 가지 입력 UI가 각각 다른 화면에 공존(중복) |
| 도움말 | `PuttingProHelpView.swift` | 5단계 사용법 섹션 + 구독 상태 표시 + 프리미엄 유도 버튼, 로컬라이즈(en/ko) |

## 5. 구독/수익화 (StoreKit 2) — EasyPutt에는 아직 없는 부분

- 상품: `giwoo.easyputt.yearly`, **연 $9.99**, **1개월 무료 체험 후 자동갱신**(`.storekit` 설정 파일 확인).
- 무료 사용자는 **볼-홀 거리 1.5m 이하만** 스캔/시뮬레이션 가능(`MeasureView.longPressGesture`에서 `distance <= 1.5` 체크). 초과 시 `SubscriptionIntroView` 시트를 띄움. (단 `FindPath.testFindPath` 안의 동일한 제한 로직은 주석 처리돼 있어, 두 군데 중 한쪽만 살아있는 상태 — 정책이 유동적이었던 흔적)
- `SubscriptionStore`(`SubscriptionStore.swift`)가 StoreKit 2 `Transaction.updates`/`Transaction.currentEntitlements`를 구독해 상태를 갱신하고, `SubscriptionCache`(`CachedSubscription.swift`)로 로컬에 캐싱(3일 유효)해서 오프라인/재실행 시 네트워크 없이도 상태를 먼저 보여줌.
- 프로모 코드 상환(`AppStore.presentOfferCodeRedeemSheet`), 구독 관리 페이지 링크, 개인정보/약관 링크(`LegalLinksView.swift`)까지 스토어 심사에 필요한 요소가 갖춰져 있음 — 실제 앱스토어 배포까지 갔던 코드로 보인다.

## 6. 코드 품질 관찰 (참고용)

- **강제 언래핑/디버그 출력 과다**: 거의 모든 함수에 `print("\(#function) ...")` 로그가 남아있고, `!` 강제 언래핑도 다수(`tile.row!`, `arViewModel.arView!` 등) — 프로덕션 빌드에서 로그 비용과 크래시 리스크가 있어 보임.
- **레거시/중복 코드**: 최상위에 `AimRuler_backup.swift`가 별도로 존재(사용처 미확인), `StimpMeterView`/`StimpMeterSheetView` 두 입력 UI 공존, 보조 스캔 루프와 배치 스캔 루프 중복, 대량의 주석 처리된 코드 블록(`FindPath.testFindPath` 안 등)이 그대로 남아있음.
- **네이밍 잔재**: 클래스 헤더 주석 대부분이 `TangTong`/`TingTing` — 리네이밍이 파일명/번들ID만 바뀌고 내부 주석까지는 안 간 상태.
- **`@Observable`과 `ObservableObject` 혼용**: `Tile`은 `@Observable`(Swift Observation), `TileGrid`/`ARViewModel`은 `ObservableObject`(Combine) — iOS 17+ 전환기의 과도기적 코드로 보임.
- **성능 우려 지점**: `TileGrid.normalVector(at:)`가 매 RK4 스텝마다 **전체 타일을 선형 탐색**(`for col { for row { ... } }`)해서 최근접 타일을 찾음 — 타일 수(3~7열 × 최대 수십 행)와 RK4 스텝 수, 게다가 방향×속도 탐색 전체 조합에 곱해지면 상당한 연산량이 될 수 있음. `isAnalyzingPath` 로딩 스피너가 별도로 있는 걸 보면 실제로 사용자가 체감할 정도의 지연이 있었던 것으로 보임.
- **"평지환산 거리"를 세 번 서로 다르게 구현한 흔적, 그중 하나는 죽은 코드**: `InterpretTiles.calcDistance()`가 `distanceFlat = totalDeceleration * distance / decelFlat`를 계산해 `@Published` 프로퍼티에 저장하지만, 이 값은 `reset()`에서 0으로 초기화될 뿐 화면 어디에도 표시되지 않는다(`GreenReadView.swift`가 실제로 찍는 "Adjusted: %.2f m"는 이 값이 아니라 `interpretTiles.totalFlatDistanceToHole` — `FindPath.rungeKuttaSimulate()`가 RK4로 궤적을 굴리면서 일-에너지 정리로 매 스텝 누적하는 완전히 다른 값이다). 게다가 `FindPath.swift` 636~638줄에는 세 번째 버전의 공식(`distanceFlat = speed² / (2·muKinetic·gravityScale)`)이 통째로 주석 처리된 채 남아있다. 즉 "평지환산 거리"라는 개념을 세 차례에 걸쳐 다시 구현한 흔적이 코드에 그대로 쌓여있고, 최종적으로 살아남은 건 RK4 기반 버전 하나뿐이다.

## 7. 현재 EasyPutt 프로젝트와의 구조적 차이 요약

| 항목 | PuttPro | EasyPutt(현재) |
|---|---|---|
| 지형 수집 방식 | 볼-홀 사각 영역 전체를 타일 메쉬로 재구성(꼭짓점별 raycast) | 볼→홀 경로를 훑을 때 (좌표,법선) 점 샘플만 수집(`TerrainSampleStore`) |
| 경로 탐색 | 속도×방향 2차원을 RK4로 전수 탐색(brute-force) | 백워드 추적으로 후보를 좁힌 뒤 forward 시뮬레이션으로 반복 보정(백+포워드), 또는 이분탐색 기반 백워드 전용 솔버 두 가지를 동시 실행·비교 |
| 조준 결과 표시 | RK4 탐색 결과(컵 단위 범위) + 별개의 해석식(K·sinθ·sinα·stimp·d²) 이중 표시 | `aimOffsetCentimeters` 등 단일 파이프라인 결과 |
| 구독/수익화 | StoreKit 2 연 구독, 1.5m 이상 유료, 프로모코드/캐시/약관 포함 완비 | 없음(현재 코드에서 미발견) |
| 시뮬레이션(가상 샷) | 있음 — 방향패드+속도로 가상 공을 실제로 굴려서 눈으로 검증(`SimulationView`) | README상 명시적 언급 없음(범위 밖일 수 있음) |
| 화면 확대/스냅샷 | 없음 | 있음(최근 커밋에서 추가) |
| 워터폴/스팀프 UI | 화살표 시각화 + 슬라이더/휠피커 두 종류 입력 | README 기준 스팀프 +/- 조절만 언급 |

## 8. 참고할 만한 아이디어

- **컵 단위 조준 서술**(`describeAimpoint`, `cupDescription`): "Left 1¼ cups out" 처럼 거리를 홀 반경/공 크기 기준 컵 개수로 환산해 보여주는 방식은 EasyPutt의 `aimOffsetCentimeters`(cm 단위)보다 골퍼에게 더 직관적일 수 있음.
- **가변 RK4 타임스텝**(`desiredStepDistance / v`, 0.01~1.0s 클램프): 속도에 반비례해 스텝을 줄여 빠른 공이 홀을 건너뛰는 걸 막는 아이디어는 EasyPutt의 forward 검증 스텝에도 참고할 만함.
- **슬라이딩→구름 전이의 토크 기반 모델**(`updateFromTorque`): 목표 각속도와의 차이로 전이 시점을 판정하고 전이 후 감쇠 계수(`reduceFactor`)를 다르게 주는 방식은, 현재 EasyPutt의 "구름저항 상수 감속" 모델보다 물리적으로 한 단계 더 정밀한 접근 — 다만 그만큼 튜닝 변수(임계각, reduceFactor)가 늘어나는 트레이드오프가 있음.
- **StoreKit 구독 캐싱 패턴**(`SubscriptionCache`, 3일 TTL): 오프라인에서도 이전 상태를 먼저 보여주고 백그라운드에서 동기화하는 패턴은 EasyPutt에 향후 유료화를 붙일 때 그대로 재사용 가능.

## 9. 한계 / 알려진 문제 (코드에서 직접 확인됨)

- 무료/유료 거리 제한 로직이 두 곳(`MeasureView`, `FindPath`)에 중복 구현되어 있고 한쪽은 주석 처리 — 실제 배포판에서 어느 쪽이 살아있는지 커밋만으로는 불확실.
- `대각선 이동은 나중에 반영`(`ARViewModel.getTileHeight` 주석) — 공이 타일 그리드에서 대각선 방향으로 넘어가는 경우 높이 보정이 구현되어 있지 않음(`height = nil` 반환).
- `normalVector`/`normalVector2` 두 개의 사실상 동일한 함수가 공존.
- 백워드 전용 개념 자체가 PuttPro에는 없음 — 전부 정방향 시뮬레이션이라 EasyPutt 대비 알고리즘적 이점(빠른 후보 좁히기)이 없고, 대신 완전탐색이라 지형이 복잡해도 조준 범위를 놓치지 않는다는 장점과 트레이드오프.

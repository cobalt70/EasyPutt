# 결과 화면 UI 재설계 설계 문서

**Goal:** 지금 `ContentView2`의 상단 컨트롤 박스(스팀프미터 스테퍼 + 거리 텍스트 + 줌/스냅샷)를 걷어내고, PuttPro의 "화면 상단 상시 결과 카드" 레이아웃을 EasyPutt의 기존 스캔/인터랙션 방식(경로를 훑으며 연속으로 지형 샘플을 모으는 방식) 위에 얹는다. 스팀프미터는 시트로, 줌/스냅샷은 화면 우측 상단 코너의 눈에 덜 띄는 컨트롤로 옮긴다.

**Non-goals:**
- PuttPro의 Mark→Scan 제스처 플로우, 탭(Measure/Simulation) 분리 구조는 가져오지 않는다 — EasyPutt은 연속 스캔 방식이라 애초에 대응되는 개념이 없다.
- "결과"(백+포워드/백워드전용 두 솔버 상세 비교) 패널은 이번엔 그대로 둔다 — 상단 카드가 요약을 보여주므로 당장 통합할 필요가 없다고 판단.
- 실제 `TabView` 네비게이션은 도입하지 않는다 — AR 세션이 화면 전환 없이 계속 떠 있어야 트래킹/스캔 데이터가 끊기지 않으므로, "설정"은 시트(모달)로만 연다.
- `slopeAdjustedDistance`(두 점+높이차만으로 즉시 계산되는 평지환산 거리)는 이번 UI에 노출하지 않는다 — 상단 카드는 풀이 완료 후에만 뜨므로 `adjustedDistance`(실제 풀이된 speed 기반, 더 정확함) 하나만 쓴다.

## 1. 배경

지금 `ContentView2`의 상단은 스팀프 스테퍼, "실제 거리/평지 환산" 한 줄 텍스트, 줌 컨트롤, 스냅샷 버튼이 하나의 반투명 박스에 전부 몰려있다(`ContentView2.swift:74-114`). 좌우 조준 정보(`aimOffsetCentimeters`)는 "결과" 토글을 눌러야만 볼 수 있는 상세 패널 안에, 두 솔버 비교와 함께 묻혀 있다.

PuttPro는 이걸 화면 상단에 상시 떠 있는 카드 하나로 압축해서 보여준다(`GreenReadView.swift`/`GreenReadingOverlayView.swift`) — 조준 범위(컵 단위), 거리, 평지환산 거리를 항상 보이게 하고, 부가 컨트롤(스팀프 등)은 별도 시트로 뺀다. 이번 작업은 그 레이아웃 아이디어만 가져오고, 데이터/계산 로직(`ArViewModel`)은 손대지 않는다.

## 2. 네 가지 변경 지점

### 2.1 상단 결과 카드 (신규)

지금의 "실제 거리: X / 평지 환산: Y" 한 줄(`ContentView2.swift:89-93`)을 3줄짜리 카드로 대체한다:

1. **조준범위** — `arViewModel.aimOffsetCentimeters(rel)` 값(cm)을 컵 단위 문구로 변환해서 표시. PuttPro `InterpretTiles.describeAimpoint(_:direction:)`를 참고해 이식한다(cm ↔ m 단위만 주의). 홀 반경(5.4cm)/공 크기(4.27cm) 기준 구간으로 나눠 "중심" / "홀 안쪽" / "1볼 아웃" / "N.N컵 아웃"으로 표현.
   - 두 솔버(백+포워드/백워드전용) 중 **백+포워드**(`rangeFinderSolutions.first`)만 대표로 쓴다. 나머지는 기존 "결과" 패널에서 계속 볼 수 있음.
2. **실제 거리** — `arViewModel.ballToHoleDistance`(3D 직선거리, 이미 구현됨).
3. **평지환산 거리** — `arViewModel.adjustedDistance`(solved speed 기반, 이미 구현됨).
- `rangeFinderSolutions`가 비어있으면(풀이 전/실패) 카드 자체를 숨긴다 — 기존 gate 조건(`if let ... = arViewModel.ballToHoleDistance, let ... = arViewModel.adjustedDistance`)에 조준범위 계산 성공 조건을 추가.

### 2.2 우측 상단 코너: 줌 + 스냅샷 (재배치 + 스타일 변경)

지금 상단 박스 안에 있던 줌(`－ 확대:1.5x ＋`)과 스냅샷(📷) 버튼을 화면 우측 상단 코너로 옮기고 스타일을 바꾼다:

- **줌**: iOS 카메라 앱 스타일의 얇은 세로 슬라이더. 평소엔 화면에 보이지 않다가, 핀치 제스처 중에만 나타나고 조작이 끝난 뒤 ~1.5초 지나면 자동으로 사라진다(fade-out). 기존 `zoomIn()`/`zoomOut()`/`displayZoom` 로직은 그대로 재사용하되, 트리거를 버튼 탭이 아니라 핀치 제스처(`MagnificationGesture`)로 바꾼다.
  - 주의: 지금 `ContentView2`에 이미 핀치 제스처가 하나 있다(`gridSpacingAtGestureStart`, 조준 격자 크기 조절용, `ContentView2.swift:236-245`). 두 핀치 제스처가 화면 전체에서 동시에 걸리면 충돌하므로, 줌 핀치는 화면 우측 상단의 좁은 영역에만 걸리게 하거나(예: 우측 20% 폭 안에서의 핀치만 인식), 기존 격자-크기 핀치와 동일 제스처를 공유하되 위치로 구분하는 방식 중 하나를 구현 단계에서 정한다.
- **스냅샷**: 줌 슬라이더 바로 아래, 배경 박스 없이 반투명 아이콘 버튼 하나(`camera.fill`, 작은 크기). `saveSnapshot()` 그대로 호출.

### 2.3 하단 바 (수정)

`ContentView2.swift:167-226`의 버튼 구성을 다음으로 바꾼다:

- **결과** — 유지(`showResults` 토글, 기존 동작 그대로)
- **법선** — 제거(`showNormalsList` state와 관련 패널, 버튼 전부 삭제)
- **설정** — 신규 버튼. 누르면 스팀프미터 조절 시트가 뜬다(2.4).
- **+** (캡처) — 유지
- **Reset** — 유지. `showNormalsList` 리셋 코드(`ContentView2.swift:220`)는 state 자체가 삭제되므로 같이 제거.

### 2.4 설정 시트 (신규)

지금 상단 박스에 있던 스팀프미터 스테퍼(`ContentView2.swift:76-88`, `－/＋` 버튼 + "Stimpmeter: X.XXm" 텍스트)를 그대로 `.sheet(isPresented:)` 안으로 옮긴다. 인터랙션/로직 변경 없음 — 위치만 이동.

## 3. 데이터 흐름

```
(변경 없음) 볼 탭 → 홀 탭 → runRangeFinder() → rangeFinderSolutions 채워짐
   ↓
상단 카드가 rangeFinderSolutions.first 기준으로 조준범위/거리/평지환산 3줄 표시 [신규 2.1]
   (rangeFinderSolutions가 비어있으면 카드 숨김)

설정 버튼 탭 → 스팀프미터 시트 열림 [신규 2.4] → stimpReading 변경
   → (기존) rollingResistance 재계산 → 다음 runRangeFinder() 호출부터 반영

핀치(우측 상단 영역) → 줌 슬라이더 표시 + displayZoom 변경 [신규 스타일 2.2]
   → 제스처 종료 1.5초 후 슬라이더 자동 숨김
```

## 4. 테스트 전략

- 컵 단위 변환 함수(`describeAimpoint` 이식분)는 순수 함수이므로 XCTest로 구간별 경계값(중심/홀 안쪽/1볼 아웃/N컵 아웃 전환 지점)을 검증한다.
- 나머지(레이아웃, 시트 전환, 핀치 제스처 자동 숨김)는 ARKit/SwiftUI 뷰 레이어라 `xcodebuild build` 컴파일 확인 후 실기기 수동 검증이 필요하다 — 특히 우측 상단 핀치 영역과 기존 격자-크기 핀치 제스처가 서로 간섭하지 않는지는 반드시 실기기에서 확인한다.

## 5. 변경 파일 예상 범위

- `EasyPutt/ContentView2.swift` — 상단 카드, 코너 컨트롤, 하단 바, 설정 시트 전부 이 파일 안에서 레이아웃 변경(현재도 단일 파일 구조).
- `EasyPutt/ArViewModel.swift` — 컵 단위 변환 함수 추가(순수 함수, 어디에 둘지는 구현 단계에서 결정 — `ArViewModel` extension 또는 별도 파일).
- 신규 XCTest 파일 또는 기존 `EasyPuttTests/` 안에 컵 단위 변환 함수 테스트 추가.

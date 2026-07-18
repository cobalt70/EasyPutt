# 결과 화면 UI 재설계 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ContentView`의 상단 컨트롤 박스(스팀프 스테퍼+거리 텍스트+줌/스냅샷)를 걷어내고, 화면 상단에 항상 떠 있는 조준범위/거리/평지환산 결과 카드(탭하면 접힘/펼침)로 대체한다. 줌/스냅샷은 우측 상단 코너의 자동숨김 컨트롤로, 스팀프미터와 두 솔버 비교 상세는 "설정" 시트로 옮긴다. 지면 트래킹 리티클(FocusEntity)도 불투명 사각형에서 투명 배경 위 "+" 표시로 바꾼다.

**Architecture:** 순수 로직(컵 단위 조준 문구 변환)은 새 파일로 분리해 XCTest로 검증한다. SwiftUI 뷰 변경은 전부 `ContentView.swift` 안에서 이뤄지고(기존에도 단일 파일 구조), 각 태스크가 그 파일의 서로 다른 영역을 순차적으로 바꾼다 — 태스크는 항상 "직전 태스크가 끝난 뒤의 파일 상태"를 전제로 한다. ARKit/RealityKit 의존 코드(FocusEntity 텍스처, 제스처)는 자동 테스트가 불가능해 `xcodebuild build` 컴파일 확인 + 실기기 수동 검증으로 대체한다.

**Tech Stack:** Swift, SwiftUI, ARKit, RealityKit, XCTest.

## Global Constraints

- 설계 문서: `docs/superpowers/specs/2026-07-19-result-overlay-redesign-design.md` (모든 태스크가 이 문서의 결정사항을 따른다).
- 기존 `ArViewModel.adjustedDistance`, `ballToHoleDistance`, `aimOffsetCentimeters`, `puttRelative`, `rangeFinderSolutions`, `backwardOnlySolutions` 등 계산 로직은 변경하지 않는다 — 이번 작업은 UI 레이아웃 재배치만 다룬다.
- `slopeAdjustedDistance`는 이번 UI에 노출하지 않는다(설계 문서 Non-goals).
- 커밋은 태스크 단위로 한다 — 각 태스크 마지막 스텝이 커밋이다.

---

### Task 1: 조준 오프셋 → 컵 단위 문구 변환 함수

**Files:**
- Create: `EasyPutt/AimDescription.swift`
- Test: `EasyPuttTests/AimDescriptionTests.swift`

**Interfaces:**
- Produces: `func describeAimOffset(centimeters: Float) -> String` — 전역 함수(순수 함수, ARKit/UIKit 의존성 없음). 이후 Task 3이 `ContentView.swift`에서 이 함수를 호출한다.

PuttPro(`InterpretTiles.describeAimpoint(_:direction:)`)의 컵 단위 변환 로직을 참고해 이식한다. 홀 반경(5.4cm)/공 지름(4.27cm) 기준 구간으로 나눠 문구를 만든다. 입력은 부호 있는 cm(양수=오른쪽, 음수=왼쪽, `ArViewModel.aimOffsetCentimeters`의 반환값과 동일한 부호 규약).

- [ ] **Step 1: 실패하는 테스트 작성**

`EasyPuttTests/AimDescriptionTests.swift`:

```swift
import XCTest
@testable import EasyPutt

final class AimDescriptionTests: XCTestCase {

    func testCenterWhenWithinTwoCentimeters() {
        XCTAssertEqual(describeAimOffset(centimeters: 0), "홀컵 중앙")
        XCTAssertEqual(describeAimOffset(centimeters: 1.9), "홀컵 중앙")
        XCTAssertEqual(describeAimOffset(centimeters: -1.9), "홀컵 중앙")
    }

    func testInsideEdgeBetweenTwoAndCupRadius() {
        XCTAssertEqual(describeAimOffset(centimeters: 3.0), "오른쪽 홀컵 안쪽")
        XCTAssertEqual(describeAimOffset(centimeters: -3.0), "왼쪽 홀컵 안쪽")
    }

    func testOneBallOutBetweenCupRadiusAndCupRadiusPlusBall() {
        // cupRadius(5.4cm)부터 시작 — 이분 상한이 배타적이라 정확히 5.4는 다음 구간에 속한다
        XCTAssertEqual(describeAimOffset(centimeters: 5.4), "오른쪽 홀컵 밖 (공 1개)")
        XCTAssertEqual(describeAimOffset(centimeters: 8.0), "오른쪽 홀컵 밖 (공 1개)")
        XCTAssertEqual(describeAimOffset(centimeters: -8.0), "왼쪽 홀컵 밖 (공 1개)")
    }

    func testCupsOutBeyondOneBallDistance() {
        // aimInMeters=0.2 → cups = (0.2 - 0.054) / 0.108 = 1.35185..
        // roundedCups = round(1.35185 * 2) / 2 = round(2.7037) / 2 = 3 / 2 = 1.5
        XCTAssertEqual(describeAimOffset(centimeters: 20.0), "오른쪽 1.5컵 아웃")
        XCTAssertEqual(describeAimOffset(centimeters: -20.0), "왼쪽 1.5컵 아웃")
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "platform=iOS Simulator,name=iPhone 16" test -only-testing:EasyPuttTests/AimDescriptionTests`
Expected: FAIL — `describeAimOffset` 함수가 없어서 컴파일 에러.

- [ ] **Step 3: 최소 구현 작성**

`EasyPutt/AimDescription.swift`:

```swift
//
//  AimDescription.swift
//  EasyPutt
//

import Foundation

/// 좌우 조준 오프셋(cm, 부호 있음: 양수=오른쪽/음수=왼쪽)을 홀 반경/공 크기 기준
/// 컵 단위 문구로 변환한다. `ArViewModel.aimOffsetCentimeters`의 반환값을 그대로 받는다.
func describeAimOffset(centimeters: Float) -> String {
    let cupRadius: Float = 0.054
    let ballSize: Float = 0.0427
    let cutoff1: Float = 0.02
    let cutoff2: Float = cupRadius
    let cutoff3: Float = cupRadius + ballSize
    let cupSize: Float = 0.108

    let aimInMeters = abs(centimeters) / 100
    let direction = centimeters < 0 ? "왼쪽" : "오른쪽"

    switch aimInMeters {
    case 0..<cutoff1:
        return "홀컵 중앙"
    case cutoff1..<cutoff2:
        return "\(direction) 홀컵 안쪽"
    case cutoff2..<cutoff3:
        return "\(direction) 홀컵 밖 (공 1개)"
    default:
        let cups = (aimInMeters - cupRadius) / cupSize
        let roundedCups = round(cups * 2) / 2
        return String(format: "%@ %.1f컵 아웃", direction, roundedCups)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "platform=iOS Simulator,name=iPhone 16" test -only-testing:EasyPuttTests/AimDescriptionTests`
Expected: PASS (4 tests)

- [ ] **Step 5: 커밋**

```bash
git add EasyPutt/AimDescription.swift EasyPuttTests/AimDescriptionTests.swift
git commit -m "조준 오프셋 컵 단위 변환 함수 추가"
```

---

### Task 2: FocusEntity 투명 "+" 리티클

**Files:**
- Create: `EasyPutt/SymbolTexture.swift`
- Modify: `EasyPutt/ArViewModel.swift:134-141` (init 안 focusEntity 생성부)

**Interfaces:**
- Consumes: 없음(독립적)
- Produces: `func textureFromSymbol(named:color:backgroundColor:backgroundAlpha:) throws -> MaterialColorParameter` — Task 3~5에서는 쓰지 않음, ArViewModel 내부에서만 사용.

PuttPro의 `ARViewModel.textureFromSymbol`을 그대로 이식한다. UIKit `UIGraphicsImageRenderer` 계열 API + RealityKit `TextureResource`를 쓰므로 ARKit 의존 코드라 XCTest로 검증하지 않는다 — 컴파일 확인 후 실기기에서 눈으로 확인한다.

- [ ] **Step 1: 헬퍼 함수 작성**

`EasyPutt/SymbolTexture.swift`:

```swift
//
//  SymbolTexture.swift
//  EasyPutt
//

import UIKit
import RealityKit

/// SF Symbol을 배경이 투명한 텍스처로 렌더링해서 RealityKit 머티리얼 파라미터로 반환한다.
/// FocusEntity(지면 트래킹 리티클)를 불투명 사각형 대신 "+" 모양만 보이게 하는 데 쓴다.
func textureFromSymbol(named symbolName: String, color: UIColor, backgroundColor: UIColor, backgroundAlpha: CGFloat) throws -> MaterialColorParameter {
    let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .regular)

    guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else {
        throw NSError(domain: "SymbolTextureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load symbol \(symbolName)"])
    }

    let size = symbolImage.size
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else {
        throw NSError(domain: "SymbolTextureError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get graphics context"])
    }

    context.setFillColor(backgroundColor.withAlphaComponent(backgroundAlpha).cgColor)
    context.fill(CGRect(origin: .zero, size: size))

    let tintedSymbol = symbolImage.withTintColor(color, renderingMode: .automatic)
    tintedSymbol.draw(in: CGRect(origin: .zero, size: size))

    guard let finalImage = UIGraphicsGetImageFromCurrentImageContext(),
          let cgImage = finalImage.cgImage else {
        throw NSError(domain: "SymbolTextureError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get final image or cgImage"])
    }

    let texture: TextureResource
    if #available(iOS 18.0, *) {
        texture = try TextureResource(image: cgImage, options: .init(semantic: .color))
    } else {
        texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }

    return .texture(texture)
}
```

- [ ] **Step 2: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: 커밋**

```bash
git add EasyPutt/SymbolTexture.swift
git commit -m "SF Symbol 투명 텍스처 헬퍼 추가"
```

- [ ] **Step 4: ArViewModel의 focusEntity 생성부를 텍스처 기반으로 변경**

`EasyPutt/ArViewModel.swift:134-141`의 현재 코드:

```swift
    init() {
        self.arView = ARView(frame: .zero)

        DispatchQueue.main.async {
            if let arView =  self.arView {
                self.focusEntity = FocusEntity(on: arView, style: .colored(onColor: MaterialColorParameter.color(.blue), offColor: MaterialColorParameter.color(.yellow), nonTrackingColor: MaterialColorParameter.color(.green)))
            }
        }
```

이렇게 바꾼다:

```swift
    init() {
        self.arView = ARView(frame: .zero)

        DispatchQueue.main.async {
            if let arView = self.arView {
                self.focusEntity = FocusEntity(on: arView, style: Self.focusEntityStyle())
            }
        }
```

같은 파일의 `extension ARView { ... }` 바로 앞(`ArViewModel.swift:411`, `class ARViewModel` 닫는 `}` 다음 줄)에 다음 static 헬퍼를 추가한다:

```swift
extension ARViewModel {
    /// FocusEntity 스타일 — SF Symbol("plus")을 투명 배경 텍스처로 렌더링해서 리티클이
    /// 불투명 사각형이 아니라 "+" 모양만 보이게 한다(사각형 안의 실제 골프공이 그대로
    /// 비침). 텍스처 생성이 실패하면(드묾) 기존 단색 사각형으로 대체한다.
    static func focusEntityStyle() -> FocusEntityComponent.Style {
        do {
            let onTexture = try textureFromSymbol(named: "plus", color: .blue, backgroundColor: .white, backgroundAlpha: 0.0)
            let offTexture = try textureFromSymbol(named: "plus", color: .yellow, backgroundColor: .white, backgroundAlpha: 0.0)
            let nonTrackingTexture = try textureFromSymbol(named: "plus", color: .green, backgroundColor: .white, backgroundAlpha: 0.0)
            return .colored(onColor: onTexture, offColor: offTexture, nonTrackingColor: nonTrackingTexture)
        } catch {
            print("⚠️ FocusEntity 텍스처 생성 실패, 단색 사각형으로 대체: \(error)")
            return .colored(onColor: .color(.blue), offColor: .color(.yellow), nonTrackingColor: .color(.green))
        }
    }
}
```

- [ ] **Step 5: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: 실기기 수동 확인**

실기기에 설치해서(`-destination "id=<DEVICE_ID>"`) 실행 → 카메라를 바닥에 비추면 리티클이 꽉 찬 사각형이 아니라 "+" 모양만 보이고, 그 자리에 실제 물체(예: 손, 공)를 놓으면 "+" 주변으로 물체가 그대로 비치는지 확인. 평면을 못 찾는 상태(초록 +), 평면 추정 중(노랑 +), 평면 확정(파랑 +) 세 상태가 색만 바뀌고 형태는 동일하게 "+"인지 확인.

- [ ] **Step 7: 커밋**

```bash
git add EasyPutt/ArViewModel.swift
git commit -m "FocusEntity를 투명 배경 + 십자선 리티클로 변경"
```

---

### Task 3: 상단 결과 카드 (조준범위/거리/평지환산, 탭하면 접힘)

**Files:**
- Modify: `EasyPutt/ContentView.swift:14-17` (state 변수), `ContentView.swift:89-93` (기존 거리 텍스트)

**Interfaces:**
- Consumes: `describeAimOffset(centimeters:) -> String` (Task 1), `arViewModel.puttRelative(_:)`, `arViewModel.aimOffsetCentimeters(_:)`, `arViewModel.ballToHoleDistance`, `arViewModel.adjustedDistance`, `arViewModel.rangeFinderSolutions` (전부 기존)
- Produces: 없음(터미널 UI 변경)

**Step 1과 2(테스트)는 생략** — SwiftUI 뷰 레이어 변경이라 XCTest 대상이 아니다(설계 문서 4절 테스트 전략). 대신 컴파일 확인 + 수동 확인으로 검증한다.

- [ ] **Step 1: state 변수 추가**

`ContentView.swift:13-17`의 현재 코드:

```swift
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showNormalsList = false
    @State private var gridSpacingAtGestureStart: Float = 60
```

이렇게 바꾼다(`resultCardExpanded` 한 줄 추가, 나머지는 그대로 — `showNormalsList`는 Task 5에서 제거):

```swift
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showNormalsList = false
    @State private var gridSpacingAtGestureStart: Float = 60
    @State private var resultCardExpanded: Bool = true
```

- [ ] **Step 2: 조준 문구 계산용 computed property 추가**

`ContentView.swift:274`(`}` — struct `ContentView`의 닫는 중괄호) 바로 앞, `solutionRows` 메서드 뒤에 추가:

```swift
    private var aimDescription: String? {
        guard let solution = arViewModel.rangeFinderSolutions.first,
              let rel = arViewModel.puttRelative(solution.direction),
              let centimeters = arViewModel.aimOffsetCentimeters(rel) else { return nil }
        return describeAimOffset(centimeters: centimeters)
    }
```

- [ ] **Step 3: 기존 거리 텍스트를 결과 카드로 교체**

`ContentView.swift:89-93`의 현재 코드:

```swift
                    if let distance = arViewModel.ballToHoleDistance, let adjusted = arViewModel.adjustedDistance {
                        Text("실제 거리: \(distance, specifier: "%.2f")m / 평지 환산: \(adjusted, specifier: "%.2f")m")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
```

이렇게 바꾼다:

```swift
                    if let aim = aimDescription, let distance = arViewModel.ballToHoleDistance, let adjusted = arViewModel.adjustedDistance {
                        Button(action: { resultCardExpanded.toggle() }) {
                            if resultCardExpanded {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("🎯 \(aim)")
                                    Text("실제 거리: \(distance, specifier: "%.2f")m")
                                    Text("평지 환산: \(adjusted, specifier: "%.2f")m")
                                }
                            } else {
                                Text("🎯 \(aim)")
                            }
                        }
                        .font(.caption2)
                        .foregroundColor(.white)
                        .buttonStyle(.plain)
                    }
```

- [ ] **Step 4: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 실기기 수동 확인**

볼/홀을 찍어서 풀이가 끝나면 카드가 3줄로 뜨는지, 탭하면 "🎯 문구" 한 줄로 줄어드는지, 다시 탭하면 3줄로 돌아오는지 확인.

- [ ] **Step 6: 커밋**

```bash
git add EasyPutt/ContentView.swift
git commit -m "상단에 조준범위/거리/평지환산 결과 카드 추가(탭하면 접힘)"
```

---

### Task 4: 우측 상단 코너 — 줌(자동숨김 슬라이더) + 스냅샷

**Files:**
- Modify: `EasyPutt/ArViewModel.swift` (줌 관련 프로퍼티/메서드)
- Modify: `EasyPutt/ContentView.swift` (기존 줌/스냅샷 블록 제거, 코너 컨트롤 추가)

**Interfaces:**
- Consumes: 없음
- Produces: `arViewModel.setDisplayZoom(_ value: Float)` — Task 5는 이 메서드를 쓰지 않는다(독립적).

- [ ] **Step 1: ArViewModel의 줌 관련 코드를 연속값 방식으로 교체**

`ArViewModel.swift:47-59`의 현재 코드:

```swift
    /// 화면(AR 콘텐츠)을 디지털로 확대해서 보여주는 배율 — 실제 카메라 렌즈나 트래킹은
    /// 그대로고, 화면에 그려지는 걸 그대로 키워서 보여주는 것뿐이다. 조준 정밀도를 높이려는
    /// 용도라 스캔이 끝난 뒤(홀 캡처 이후) 주로 쓴다.
    @Published var displayZoom: Float = 1.0
    let displayZoomLevels: [Float] = [1.0, 1.5, 2.0, 3.0]
    func zoomIn() {
        guard let index = displayZoomLevels.firstIndex(of: displayZoom), index < displayZoomLevels.count - 1 else { return }
        displayZoom = displayZoomLevels[index + 1]
    }
    func zoomOut() {
        guard let index = displayZoomLevels.firstIndex(of: displayZoom), index > 0 else { return }
        displayZoom = displayZoomLevels[index - 1]
    }
```

이렇게 바꾼다(핀치로 연속적으로 조절하므로 이산 단계 배열/스테퍼 메서드 대신 클램프 하나만 필요):

```swift
    /// 화면(AR 콘텐츠)을 디지털로 확대해서 보여주는 배율 — 실제 카메라 렌즈나 트래킹은
    /// 그대로고, 화면에 그려지는 걸 그대로 키워서 보여주는 것뿐이다. 조준 정밀도를 높이려는
    /// 용도라 스캔이 끝난 뒤(홀 캡처 이후) 주로 쓴다. 우측 상단 코너의 핀치 제스처로
    /// 1.0~3.0 사이를 연속적으로 조절한다.
    @Published var displayZoom: Float = 1.0
    let displayZoomMin: Float = 1.0
    let displayZoomMax: Float = 3.0
    func setDisplayZoom(_ value: Float) {
        displayZoom = min(max(value, displayZoomMin), displayZoomMax)
    }
```

- [ ] **Step 2: 컴파일 확인 (경고 없이 기존 호출부가 아직 남아있어 에러는 없어야 함)**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD FAILED — `ContentView.swift`가 아직 `zoomIn()`/`zoomOut()`을 호출 중이라 여기서 에러가 나는 게 정상. Step 3~4에서 그 호출부를 제거하면 해결된다.

- [ ] **Step 3: ContentView에서 기존 줌/스냅샷 블록 제거**

`ContentView.swift:94-110`의 현재 코드(Task 3 완료 후 기준 — 줄 번호는 Task 3의 카드 삽입으로 약간 밀렸을 수 있으니, 아래 코드 블록 텍스트로 찾는다):

```swift
                    HStack {
                        Button(action: { arViewModel.zoomOut() }) {
                            Image(systemName: "minus.magnifyingglass")
                        }
                        Text("확대: \(arViewModel.displayZoom, specifier: "%.1f")x")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        Button(action: { arViewModel.zoomIn() }) {
                            Image(systemName: "plus.magnifyingglass")
                        }
                        Button(action: { arViewModel.saveSnapshot() }) {
                            Image(systemName: "camera.fill")
                        }
                        .padding(.leading, 8)
                    }
```

이 블록 전체를 삭제한다(상단 박스에는 스팀프 스테퍼 + 결과 카드만 남는다).

- [ ] **Step 4: 우측 상단 코너 컨트롤 뷰 추가**

`ContentView.swift` 맨 끝(`ActionButton` struct 뒤)에 추가:

```swift
struct ZoomCornerControl: View {
    @ObservedObject var arViewModel: ARViewModel
    @State private var isDragging = false
    @State private var hideTask: DispatchWorkItem?
    @State private var zoomAtGestureStart: Float = 1.0

    var body: some View {
        VStack(spacing: 12) {
            if isDragging {
                VStack(spacing: 4) {
                    Text(String(format: "%.1fx", arViewModel.displayZoom))
                        .font(.caption2)
                        .foregroundColor(.white)
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 4, height: 120)
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 4, height: 120 * CGFloat((arViewModel.displayZoom - arViewModel.displayZoomMin) / (arViewModel.displayZoomMax - arViewModel.displayZoomMin)))
                    }
                }
                .transition(.opacity)
            }

            Button(action: { arViewModel.saveSnapshot() }) {
                Image(systemName: "camera.fill")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 18))
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 90, height: 220, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    isDragging = true
                    hideTask?.cancel()
                    arViewModel.setDisplayZoom(zoomAtGestureStart * Float(value))
                }
                .onEnded { _ in
                    zoomAtGestureStart = arViewModel.displayZoom
                    let task = DispatchWorkItem {
                        withAnimation { isDragging = false }
                    }
                    hideTask = task
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
                }
        )
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}
```

- [ ] **Step 5: 코너 컨트롤을 화면에 배치**

`ContentView.swift`의 `body` 안, 최상위 `ZStack { ... }`의 마지막 자식(상단 컨트롤 `VStack` 바로 뒤, `.ignoresSafeArea(edges: [.top, .bottom])` 앞)에 추가:

```swift
            ZoomCornerControl(arViewModel: arViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
```

- [ ] **Step 6: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: 실기기 수동 확인**

화면 우측 상단(카메라 아이콘 근처)에서 핀치하면 슬라이더가 나타나고 배율이 바뀌는지, 화면 중앙/좌측에서 핀치하면 기존 조준 격자 크기 조절 제스처만 동작하고 줌 슬라이더는 안 나타나는지, 핀치를 멈추고 1.5초 뒤 슬라이더가 자동으로 사라지는지, 카메라 아이콘을 누르면 스냅샷이 저장되는지 확인.

- [ ] **Step 8: 커밋**

```bash
git add EasyPutt/ArViewModel.swift EasyPutt/ContentView.swift
git commit -m "줌/스냅샷을 우측 상단 코너 자동숨김 컨트롤로 이동"
```

---

### Task 5: 하단 바 축소(+/Reset/설정) + 설정 시트(스팀프미터 + 고급 결과비교)

**Files:**
- Modify: `EasyPutt/ContentView.swift`

**Interfaces:**
- Consumes: `arViewModel.stimpReading`, `arViewModel.rangeFinderSolutions`, `arViewModel.backwardOnlySolutions`, `arViewModel.rangeFinderElapsedMs`, `arViewModel.backwardOnlyElapsedMs`, `arViewModel.puttRelative(_:)`, `arViewModel.aimOffsetCentimeters(_:)`, `arViewModel.ballToHoleDistance` (전부 기존)
- Produces: 없음(터미널 UI 변경)

- [ ] **Step 1: state 변수 정리 — `showNormalsList` 제거, `showSettings` 추가**

`ContentView.swift:13-18`(Task 3 완료 후 기준)의 현재 코드:

```swift
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showNormalsList = false
    @State private var gridSpacingAtGestureStart: Float = 60
    @State private var resultCardExpanded: Bool = true
```

이렇게 바꾼다:

```swift
struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showSettings = false
    @State private var gridSpacingAtGestureStart: Float = 60
    @State private var resultCardExpanded: Bool = true
```

- [ ] **Step 2: 스팀프 스테퍼를 상단 박스에서 제거**

`ContentView.swift:76-88`의 현재 코드:

```swift
                    HStack {
                        Button(action: { arViewModel.stimpReading = max(1.5, arViewModel.stimpReading - 0.1) }) {
                            Image(systemName: "minus.circle.fill")
                        }
                        Text("Stimpmeter: \(arViewModel.stimpReading, specifier: "%.2f")m")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        Button(action: { arViewModel.stimpReading = min(4.0, arViewModel.stimpReading + 0.1) }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
```

이 블록 전체를 삭제한다(상단 박스에는 Task 3의 결과 카드만 남는다).

- [ ] **Step 3: "법선" 패널과 리스트 상태 제거**

`ContentView.swift`에서 다음 블록을 통째로 삭제한다(Task 3 완료 후 기준 줄 번호는 조금 밀렸을 수 있으니 텍스트로 찾는다):

```swift
                if showNormalsList {
                    ScrollView {
                        VStack {
                            Text("지형 샘플: \(arViewModel.terrainSamples.count)개")
                            ForEach(Array(arViewModel.terrainSamples.samples.enumerated()), id: \.offset) { index, sample in
                                Text("#\(index) n(\(sample.normal.x, specifier: "%.3f"), \(sample.normal.y, specifier: "%.3f"), \(sample.normal.z, specifier: "%.3f"))")
                                    .font(.caption2)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 200)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
```

- [ ] **Step 4: 기존 "결과" 인라인 패널(`showResults` 조건부 뷰) 제거**

다음 블록도 통째로 삭제한다(내용은 Step 6에서 새 `SettingsSheetView`로 그대로 옮긴다):

```swift
                if showResults, let distance = arViewModel.ballToHoleDistance {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text("거리: \(distance, specifier: "%.2f")m")
                            Text("볼: (0.00, 0.00) / 홀: (0.00, \(distance, specifier: "%.2f"))")
                                .font(.caption2)

                            if let combinedMs = arViewModel.rangeFinderElapsedMs, let backwardMs = arViewModel.backwardOnlyElapsedMs {
                                Text("소요시간 — 백+포워드: \(combinedMs, specifier: "%.1f")ms / 백워드 전용: \(backwardMs, specifier: "%.1f")ms")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text("[백+포워드] 유효 방향: \(arViewModel.rangeFinderSolutions.count)개")
                                .font(.caption2.bold())
                            ForEach(Array(arViewModel.rangeFinderSolutions.enumerated()), id: \.offset) { _, solution in
                                solutionRows(solution, boundaryAColor: .red, boundaryBColor: .green)
                            }

                            Text("[백워드 전용] 유효 방향: \(arViewModel.backwardOnlySolutions.count)개")
                                .font(.caption2.bold())
                                .padding(.top, 4)
                            ForEach(Array(arViewModel.backwardOnlySolutions.enumerated()), id: \.offset) { _, solution in
                                solutionRows(solution, boundaryAColor: .blue, boundaryBColor: .orange)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 260)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                }
```

- [ ] **Step 5: `solutionRows` 메서드를 `ContentView`에서 `SettingsSheetView`로 이동**

`ContentView.swift`의 `private func solutionRows(...)` 메서드(Task 3에서 추가한 `aimDescription` 바로 앞) 전체를 잘라낸다 — Step 6에서 `SettingsSheetView` 안에 붙여넣는다. `ContentView`에는 더 이상 필요 없다.

- [ ] **Step 6: 설정 시트 뷰 추가**

`ContentView.swift` 맨 끝(`ZoomCornerControl` 뒤)에 추가한다. `solutionRows`는 Step 5에서 잘라낸 코드를 그대로 붙여넣는다(시그니처의 `arViewModel` 참조만 `self.arViewModel` → 이 struct의 프로퍼티로 그대로 유효):

```swift
struct SettingsSheetView: View {
    @ObservedObject var arViewModel: ARViewModel
    @Binding var showResults: Bool

    var body: some View {
        NavigationView {
            Form {
                Section("스팀프미터") {
                    HStack {
                        Button(action: { arViewModel.stimpReading = max(1.5, arViewModel.stimpReading - 0.1) }) {
                            Image(systemName: "minus.circle.fill")
                        }
                        Text("Stimpmeter: \(arViewModel.stimpReading, specifier: "%.2f")m")
                        Button(action: { arViewModel.stimpReading = min(4.0, arViewModel.stimpReading + 0.1) }) {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                Section {
                    DisclosureGroup("고급: 두 솔버 비교", isExpanded: $showResults) {
                        if let distance = arViewModel.ballToHoleDistance {
                            VStack(alignment: .leading) {
                                Text("거리: \(distance, specifier: "%.2f")m")

                                if let combinedMs = arViewModel.rangeFinderElapsedMs, let backwardMs = arViewModel.backwardOnlyElapsedMs {
                                    Text("소요시간 — 백+포워드: \(combinedMs, specifier: "%.1f")ms / 백워드 전용: \(backwardMs, specifier: "%.1f")ms")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Text("[백+포워드] 유효 방향: \(arViewModel.rangeFinderSolutions.count)개")
                                    .font(.caption2.bold())
                                ForEach(Array(arViewModel.rangeFinderSolutions.enumerated()), id: \.offset) { _, solution in
                                    solutionRows(solution, boundaryAColor: .red, boundaryBColor: .green)
                                }

                                Text("[백워드 전용] 유효 방향: \(arViewModel.backwardOnlySolutions.count)개")
                                    .font(.caption2.bold())
                                    .padding(.top, 4)
                                ForEach(Array(arViewModel.backwardOnlySolutions.enumerated()), id: \.offset) { _, solution in
                                    solutionRows(solution, boundaryAColor: .blue, boundaryBColor: .orange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func solutionRows(_ solution: PuttSolution, boundaryAColor: Color, boundaryBColor: Color) -> some View {
        if let rel = arViewModel.puttRelative(solution.direction) {
            let aimLine: String = {
                guard let centimeters = arViewModel.aimOffsetCentimeters(rel) else { return "" }
                return " / 홀컵 기준 \(String(format: "%+.1f", centimeters))cm"
            }()
            Text("speed \(solution.speed, specifier: "%.2f") / 우: \(rel.right, specifier: "%.2f") 전진: \(rel.forward, specifier: "%.2f")\(aimLine)")
                .font(.caption2)

            if let boundaryA = solution.directionBoundaryA,
               let relA = arViewModel.puttRelative(boundaryA),
               let centimetersA = arViewModel.aimOffsetCentimeters(relA) {
                Text("Boundary A: 홀컵 기준 \(String(format: "%+.1f", centimetersA))cm 조준")
                    .font(.caption2)
                    .foregroundColor(boundaryAColor)
            }
            if let boundaryB = solution.directionBoundaryB,
               let relB = arViewModel.puttRelative(boundaryB),
               let centimetersB = arViewModel.aimOffsetCentimeters(relB) {
                Text("Boundary B: 홀컵 기준 \(String(format: "%+.1f", centimetersB))cm 조준")
                    .font(.caption2)
                    .foregroundColor(boundaryBColor)
            }
        }
    }
}
```

- [ ] **Step 7: 하단 바를 +/Reset/설정 3개로 교체**

`ContentView.swift`의 하단 바(`HStack(spacing: 0) { ... }`, "결과"/"법선" `ActionButton` 두 개가 있던 그 블록)의 현재 코드:

```swift
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ActionButton(title: "결과", color: showResults ? .blue : .gray) {
                            showResults.toggle()
                        }
                        .frame(width: 60)

                        ActionButton(title: "법선", color: showNormalsList ? .blue : .gray) {
                            showNormalsList.toggle()
                        }
                        .frame(width: 60)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: {
                        if arViewModel.ballPosition == nil {
                            arViewModel.captureBallSubject.send()
                        } else if arViewModel.holePosition == nil {
                            arViewModel.captureHoleSubject.send()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(arViewModel.ballPosition == nil ? Color.green : Color.red)
                                    .frame(width: 44, height: 44)
                            )
                    }
                    .disabled(arViewModel.ballPosition != nil && arViewModel.holePosition != nil)

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)

                        ActionButton(title: "Reset", color: .orange) {
                            guard let arView = arViewModel.arView else { return }
                            arViewModel.ballPosition = nil
                            arViewModel.holePosition = nil
                            arViewModel.rangeFinderSolutions = []
                            arViewModel.backwardOnlySolutions = []
                            arViewModel.rangeFinderElapsedMs = nil
                            arViewModel.backwardOnlyElapsedMs = nil
                            arViewModel.ballToHoleDistance = nil
                            arViewModel.stopCollectingTerrainSamples()
                            arViewModel.terrainSamples.removeAll()
                            removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
                            removeAnchorWithName(for: arView, name: "TerrainSampleMarkersAnchor")
                            removeAnchorWithName(for: arView, name: "BallMarkerAnchor")
                            removeAnchorWithName(for: arView, name: "FlagMarkerAnchor")
                            showResults = false
                            showNormalsList = false
                            print("Reset complete")
                        }
                        .frame(width: 70)
                    }
                    .frame(maxWidth: .infinity)
                }
```

이렇게 바꾼다(왼쪽 클러스터를 "결과/법선" 두 개에서 "설정" 하나로, Reset 액션에서 `showNormalsList = false` 삭제):

```swift
                HStack(spacing: 0) {
                    HStack(spacing: 8) {
                        ActionButton(title: "설정", color: .gray) {
                            showSettings = true
                        }
                        .frame(width: 60)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)

                    Button(action: {
                        if arViewModel.ballPosition == nil {
                            arViewModel.captureBallSubject.send()
                        } else if arViewModel.holePosition == nil {
                            arViewModel.captureHoleSubject.send()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .background(
                                Circle()
                                    .fill(arViewModel.ballPosition == nil ? Color.green : Color.red)
                                    .frame(width: 44, height: 44)
                            )
                    }
                    .disabled(arViewModel.ballPosition != nil && arViewModel.holePosition != nil)

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)

                        ActionButton(title: "Reset", color: .orange) {
                            guard let arView = arViewModel.arView else { return }
                            arViewModel.ballPosition = nil
                            arViewModel.holePosition = nil
                            arViewModel.rangeFinderSolutions = []
                            arViewModel.backwardOnlySolutions = []
                            arViewModel.rangeFinderElapsedMs = nil
                            arViewModel.backwardOnlyElapsedMs = nil
                            arViewModel.ballToHoleDistance = nil
                            arViewModel.stopCollectingTerrainSamples()
                            arViewModel.terrainSamples.removeAll()
                            removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
                            removeAnchorWithName(for: arView, name: "TerrainSampleMarkersAnchor")
                            removeAnchorWithName(for: arView, name: "BallMarkerAnchor")
                            removeAnchorWithName(for: arView, name: "FlagMarkerAnchor")
                            showResults = false
                            print("Reset complete")
                        }
                        .frame(width: 70)
                    }
                    .frame(maxWidth: .infinity)
                }
```

- [ ] **Step 8: 설정 시트 연결**

`ContentView.swift`의 최상위 `ZStack { ... }` 바로 뒤(`.ignoresSafeArea(edges: [.top, .bottom])` modifier 다음)에 `.sheet` modifier를 추가한다. 현재:

```swift
        .ignoresSafeArea(edges: [.top, .bottom])
        .gesture(
```

이렇게 바꾼다:

```swift
        .ignoresSafeArea(edges: [.top, .bottom])
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(arViewModel: arViewModel, showResults: $showResults)
        }
        .gesture(
```

- [ ] **Step 9: 컴파일 확인**

Run: `xcodebuild -project EasyPutt.xcodeproj -scheme EasyPutt -destination "generic/platform=iOS" build`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: 실기기 수동 확인**

하단 바에 +/Reset/설정 3개만 보이는지, "설정"을 누르면 시트가 뜨고 스팀프 스테퍼가 동작하는지, "고급: 두 솔버 비교"를 펼치면 기존 결과 패널 내용(두 솔버 비교, 소요시간)이 그대로 나오는지, Reset을 누르면 볼/홀/결과가 전부 초기화되고 시트 밖으로 나와도 상태가 깨끗한지 확인.

- [ ] **Step 11: 커밋**

```bash
git add EasyPutt/ContentView.swift
git commit -m "하단 바를 +/Reset/설정 3개로 축소, 스팀프미터·결과비교를 설정 시트로 이동"
```

---

## 계획 자체 검토(Self-Review) 결과

- **스펙 커버리지**: 설계 문서 2.1(상단 카드)→Task 3, 2.2(코너 컨트롤)→Task 4, 2.3(하단 바)→Task 5 Step 7, 2.4(설정 시트)→Task 5 Step 6, 2.5(FocusEntity)→Task 2 전부 대응. 3절(데이터 흐름)과 4절(테스트 전략)도 각 태스크의 컴파일/수동 확인 스텝에 반영.
- **타입/시그니처 일관성**: `describeAimOffset(centimeters:)`(Task 1) 시그니처를 Task 3의 `aimDescription`이 그대로 사용. `arViewModel.setDisplayZoom(_:)`(Task 4)를 `ZoomCornerControl`이 그대로 사용. `solutionRows`가 Task 5에서 `ContentView`→`SettingsSheetView`로 이동하며 시그니처(`_ solution: PuttSolution, boundaryAColor: Color, boundaryBColor: Color`) 동일하게 유지.
- **플레이스홀더 스캔**: 없음 — 모든 스텝에 실제 코드 포함.

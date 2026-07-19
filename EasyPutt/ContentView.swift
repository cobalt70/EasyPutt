//
//  ContentView.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/25/25.
//  Updated by Gi Woo Kim on 7/19/26.
//
import SwiftUI
import Combine
import RealityKit
import ARKit
import simd

struct ContentView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showSettings = false
    @State private var gridSpacingAtGestureStart: Float = 60
    @State private var resultCardExpanded: Bool = true

    var body: some View {
        ZStack {
            // AR 배경 — displayZoom만큼 화면 콘텐츠를 그대로 확대해서 보여준다(디지털 줌,
            // 실제 카메라/트래킹은 그대로). UI 컨트롤들은 이 스케일 밖에 있어서 안 커진다.
            ARViewContainer()
                .environmentObject(arViewModel)
                .ignoresSafeArea()
                .scaleEffect(CGFloat(arViewModel.displayZoom))

            // 화면 중앙 조준 아이콘 (볼/홀 캡처 대상 지점)
            if arViewModel.holePosition == nil {
                Image(systemName: "viewfinder")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .foregroundColor(arViewModel.ballPosition == nil ? .green : .red)
                    .allowsHitTesting(false)
            }

            // 조준용 3x3 정사각형 격자 (9칸이 뚜렷이 보이는 시각적 가이드 —
            // 각 칸 중심이 실제 수집 지점과 정확히 일치한다, collectTerrainSamples() 참고)
            // 손가락 핀치로 칸 크기(pt)를 조절한다 (최소 30pt).
            if arViewModel.holePosition == nil {
                GeometryReader { geo in
                    let cx = geo.size.width / 2
                    let cy = geo.size.height / 2
                    let s = CGFloat(arViewModel.terrainSampleGridSpacing)
                    let half = 1.5 * s
                    Path { path in
                        path.addRect(CGRect(x: cx - half, y: cy - half, width: 3 * s, height: 3 * s))
                        path.move(to: CGPoint(x: cx - s / 2, y: cy - half))
                        path.addLine(to: CGPoint(x: cx - s / 2, y: cy + half))
                        path.move(to: CGPoint(x: cx + s / 2, y: cy - half))
                        path.addLine(to: CGPoint(x: cx + s / 2, y: cy + half))
                        path.move(to: CGPoint(x: cx - half, y: cy - s / 2))
                        path.addLine(to: CGPoint(x: cx + half, y: cy - s / 2))
                        path.move(to: CGPoint(x: cx - half, y: cy + s / 2))
                        path.addLine(to: CGPoint(x: cx + half, y: cy + s / 2))
                    }
                    .stroke(Color.cyan.opacity(0.7), lineWidth: 1)

                    if let meters = arViewModel.gridCellMeters {
                        Text("한 칸: \(meters, specifier: "%.2f")m")
                            .font(.caption2)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                            .position(x: cx, y: cy - half - 14)
                    }
                }
                .allowsHitTesting(false)
            }

            // 상단 컨트롤 + (필요시) 정보 패널 + 하단 바 — 전부 세이프에어리어 무시하고
            // 화면 맨 위/맨 아래 끝에 붙인다.
            VStack(spacing: 8) {
                VStack(spacing: 4) {
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
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

                Spacer()

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
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ZoomCornerControl(arViewModel: arViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(1) // 다른 오버레이 밑에 깔리지 않도록 최상단에 명시적으로 고정한다.
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .sheet(isPresented: $showSettings) {
            SettingsSheetView(arViewModel: arViewModel, showResults: $showResults)
        }
        .gesture(
            // 스캔 단계(홀 캡처 전)에서만 격자 칸 크기를 조절한다 — 그 이후에는 이 제스처가
            // 할 일이 없는데도 화면 전체를 덮고 있으면 ZoomCornerControl의 확대축소 핀치와
            // 계속 충돌한다.
            arViewModel.holePosition == nil
                ? MagnificationGesture()
                    .onChanged { value in
                        let newValue = gridSpacingAtGestureStart * Float(value)
                        arViewModel.terrainSampleGridSpacing = min(max(newValue, 30), 150)
                    }
                    .onEnded { _ in
                        gridSpacingAtGestureStart = arViewModel.terrainSampleGridSpacing
                    }
                : nil
        )
    }

    private var aimDescription: String? {
        guard let solution = arViewModel.rangeFinderSolutions.first,
              let rel = arViewModel.puttRelative(solution.direction),
              let centimeters = arViewModel.aimOffsetCentimeters(rel) else { return nil }
        return describeAimOffset(centimeters: centimeters)
    }
}

#Preview {
    ContentView()
}

struct ActionButton: View {
    let title: String
    var color: Color = .blue
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(color)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .disabled(disabled)
    }
}

/// 눌렀을 때(진한 흰색)와 안 눌렀을 때(옅은 흰색)를 눈으로 구분할 수 있게 하는
/// 버튼 스타일 — 기본 Button은 눌림 여부가 잘 안 보인다.
private struct PressStateOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white.opacity(configuration.isPressed ? 1.0 : 0.6))
    }
}

struct ZoomCornerControl: View {
    @ObservedObject var arViewModel: ARViewModel
    @State private var isDragging = false
    @State private var hideTask: DispatchWorkItem?
    @State private var zoomAtGestureStart: Float = 1.0

    private let zoomStep: Float = 0.25

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text(String(format: "%.1fx", arViewModel.displayZoom))
                    .font(.caption2)
                    .foregroundColor(.white)

                // 핀치 제스처를 못 찾는 사람들을 위해 항상 보이는 확대/축소 버튼도 둔다 —
                // 핀치와 같은 setDisplayZoom을 쓰므로 둘 다 동시에 써도 값이 어긋나지 않는다.
                Button(action: { arViewModel.setDisplayZoom(arViewModel.displayZoom + zoomStep) }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 16))
                }
                .buttonStyle(PressStateOpacityButtonStyle())

                Button(action: { arViewModel.setDisplayZoom(arViewModel.displayZoom - zoomStep) }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 16))
                }
                .buttonStyle(PressStateOpacityButtonStyle())

                if isDragging {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 4, height: 80)
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 4, height: 80 * CGFloat((arViewModel.displayZoom - arViewModel.displayZoomMin) / (arViewModel.displayZoomMax - arViewModel.displayZoomMin)))
                    }
                    .transition(.opacity)
                }
            }

            Button(action: { arViewModel.saveSnapshot() }) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(PressStateOpacityButtonStyle())
        }
        .padding(.trailing, 12)
        .padding(.top, 8)
        .frame(width: 90, height: 220, alignment: .top)
        .contentShape(Rectangle())
        // 화면 전체를 덮는 ContentView의 격자-크기 조절용 MagnificationGesture와 같은
        // 제스처 타입이 겹쳐서, 일반 .gesture()로는 부모 쪽에 우선권을 뺏겨 이 핀치가
        // 아예 인식되지 않는 경우가 있었다 — highPriorityGesture로 이 컨트롤 영역
        // 안에서는 확대축소가 항상 이기도록 한다.
        .highPriorityGesture(
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

struct SettingsSheetView: View {
    @ObservedObject var arViewModel: ARViewModel
    @Binding var showResults: Bool

    var body: some View {
        NavigationView {
            Form {
                Section("스팀프미터") {
                    HStack {
                        Text("스팀프미터")
                        Spacer()
                        Text("\(arViewModel.stimpReading, specifier: "%.2f")m")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                        VStack(spacing: 4) {
                            Button(action: { arViewModel.stimpReading = min(4.0, arViewModel.stimpReading + 0.1) }) {
                                Image(systemName: "chevron.up")
                            }
                            Button(action: { arViewModel.stimpReading = max(1.5, arViewModel.stimpReading - 0.1) }) {
                                Image(systemName: "chevron.down")
                            }
                        }
                        .font(.caption)
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

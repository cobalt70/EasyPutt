//
//  ContentView.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/25/25.
//
import SwiftUI
import Combine
import RealityKit
import ARKit
import simd

struct ContentView2: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showResults = false
    @State private var showNormalsList = false
    @State private var gridSpacingAtGestureStart: Float = 60

    var body: some View {
        ZStack {
            // AR 배경
            ARViewContainer()
                .environmentObject(arViewModel)
                .edgesIgnoringSafeArea(.all)

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
                    if let distance = arViewModel.ballToHoleDistance, let adjusted = arViewModel.adjustedDistance {
                        Text("실제 거리: \(distance, specifier: "%.2f")m / 평지 환산: \(adjusted, specifier: "%.2f")m")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)

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

                Spacer()

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
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newValue = gridSpacingAtGestureStart * Float(value)
                    arViewModel.terrainSampleGridSpacing = min(max(newValue, 30), 150)
                }
                .onEnded { _ in
                    gridSpacingAtGestureStart = arViewModel.terrainSampleGridSpacing
                }
        )
    }

    @ViewBuilder
    private func solutionRows(_ solution: PuttSolution, boundaryAColor: Color, boundaryBColor: Color) -> some View {
        if let rel = arViewModel.puttRelative(solution.direction) {
            let aimLine: String = {
                guard let inches = arViewModel.aimOffsetInches(rel) else { return "" }
                let side = inches >= 0 ? "오른쪽" : "왼쪽"
                return " / 홀컵 기준 \(side) \(String(format: "%.1f", abs(inches)))in"
            }()
            Text("speed \(solution.speed, specifier: "%.2f") / 우: \(rel.right, specifier: "%.2f") 전진: \(rel.forward, specifier: "%.2f")\(aimLine)")
                .font(.caption2)

            if let boundaryA = solution.directionBoundaryA,
               let relA = arViewModel.puttRelative(boundaryA),
               let inchesA = arViewModel.aimOffsetInches(relA) {
                let side = inchesA >= 0 ? "오른쪽" : "왼쪽"
                Text("Boundary A: 홀컵 기준 \(side) \(String(format: "%.1f", abs(inchesA)))in 조준")
                    .font(.caption2)
                    .foregroundColor(boundaryAColor)
            }
            if let boundaryB = solution.directionBoundaryB,
               let relB = arViewModel.puttRelative(boundaryB),
               let inchesB = arViewModel.aimOffsetInches(relB) {
                let side = inchesB >= 0 ? "오른쪽" : "왼쪽"
                Text("Boundary B: 홀컵 기준 \(side) \(String(format: "%.1f", abs(inchesB)))in 조준")
                    .font(.caption2)
                    .foregroundColor(boundaryBColor)
            }
        }
    }
}

#Preview {
    ContentView2()
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

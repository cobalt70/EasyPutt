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
    @StateObject private var btnViewModel = ButtonViewModel()
    @State var totalTileCount: Int = 0
    let padding: Float = 0

    var body: some View {
        ZStack {
            // AR 배경
            ARViewContainer()
                .environmentObject(arViewModel)
                .edgesIgnoringSafeArea(.all)

            // 상단 슬라이더 카드
            VStack {
                VStack(spacing: 4) {
                    HStack {
                        Slider(value: $arViewModel.speed, in: 0...3, step: 0.5)
                        Text("Speed: \(arViewModel.speed, specifier: "%.1f")")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(height: 20)
                    .scaleEffect(0.85)

                    HStack {
                        Slider(value: $arViewModel.direction, in: -1...1, step: 0.05)
                        Text("Direction: \(arViewModel.direction, specifier: "%.2f")")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(height: 20)
                    .scaleEffect(0.85)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .padding(.top, 12)

                Spacer()
            }

            if let distance = arViewModel.ballToHoleDistance {
                VStack {
                    Text("거리: \(distance, specifier: "%.2f")m")
                    Text("유효 방향: \(arViewModel.rangeFinderSolutions.count)개")
                    ForEach(Array(arViewModel.rangeFinderSolutions.enumerated()), id: \.offset) { _, solution in
                        Text("speed \(solution.speed, specifier: "%.2f") / dir (\(solution.direction.x, specifier: "%.2f"), \(solution.direction.z, specifier: "%.2f"))")
                            .font(.caption2)
                    }
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .padding(.top, 60)
            }

            // 타일 상태 표시 (하단)
            if let tileGrid = arViewModel.tileGrid {
                VStack {
                    Spacer()

                    VStack(spacing: 2) {
                        Text(tileGrid.scanCompleted ? "✅ Scan Complete" : "📡 Scanning...")
                        Text("\(tileGrid.projectedTiles.flatMap { $0 }.filter { $0 != nil }.count) / \(tileGrid.totalTileCount)")
                    }
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                ActionButton(title: "Ball", color: .green) {
                    arViewModel.captureBallSubject.send()
                }

                ActionButton(title: "Hole", color: .red) {
                    arViewModel.captureHoleSubject.send()
                }

                ActionButton(title: "Start", color: .green, disabled: btnViewModel.startCompleted && btnViewModel.endCompleted) {
                    guard let arView = arViewModel.arView else { return }
                    btnViewModel.startCompleted = true
                    startSetup(arViewModel: arViewModel)
                    if  let position = arViewModel.tileGrid?.startPoint  {
                        loadModel(for: arView, position: position,  name: "scull")
                    }
                }

                ActionButton(title: "End", color: .red, disabled: btnViewModel.endCompleted || !btnViewModel.startCompleted) {
                    guard let arView = arViewModel.arView else { return }
                    endSetup(arViewModel: arViewModel)
                    if let position = arViewModel.tileGrid?.endPoint {
                        loadModel(for: arView, position: position, name: "scull")
                    }
                    if let tileGrid = arViewModel.tileGrid {
                        tileGrid.updateGrid(arView: arView,
                                            startPoint: tileGrid.startPoint,
                                            endPoint: tileGrid.endPoint,
                                            tileWidth: nil,
                                            tileHeight: nil,
                                            padding: nil)
                        tileGrid.show()
                    }
                    btnViewModel.endCompleted = true
                }

                ActionButton(title: "Scan", color: btnViewModel.canScan ? .blue : .gray, disabled: !btnViewModel.canScan && btnViewModel.scanCompleted) {
                    if !arViewModel.isScanning {
                        arViewModel.isScanning = true
                        print("Scanning started.")
                    }
                }
                .onLongPressGesture(minimumDuration: 1.0, perform: {
                    arViewModel.isScanning = true
                    print("Long press started scanning.")
                }, onPressingChanged: { pressing in
                    if !pressing {
//                        if arViewModel.arView?.debugOptions.contains(.showPhysics) == false {
//                            arViewModel.arView?.debugOptions.insert(.showPhysics)
//                        }
                        if let padding = arViewModel.tileGrid?.padding, padding > 0.001 {
                            arViewModel.tileGrid?.makePadding()
                        }
                        arViewModel.isScanning = false
                        print("Scan button released.")
                    }
                })

                ActionButton(title: "Smth", color: .orange) {
                    guard let arView = arViewModel.arView else { return }
                    if let tileGrid = arViewModel.tileGrid {
                        if let anchor = tileGrid.projectedTileAnchor {
                            arView.scene.removeAnchor(anchor)
                        }
                        tileGrid.displayAnchor?.children.removeAll()
                        tileGrid.makeSmoothPadding()
                    }
                    if let smoothedAnchor = arViewModel.tileGrid?.smoothedProjectedTileAnchor {
                        arViewModel.arView?.scene.addAnchor(smoothedAnchor)
                    }
                    if let smoothedDisplay = arViewModel.tileGrid?.smoothedDisplayAnchor {
                        arViewModel.arView?.scene.addAnchor(smoothedDisplay)
                    }
                }

                ActionButton(title: "Reset", color: .orange) {
                    btnViewModel.reset()
                    guard let arView = arViewModel.arView else { return }
                    arViewModel.isScanning = false
                    if let tileGrid = arViewModel.tileGrid {
                        tileGrid.smoothedProjectedTileAnchor?.removeFromParent()
                        tileGrid.projectedTileAnchor?.removeFromParent()
                        tileGrid.smoothedDisplayAnchor?.removeFromParent()
                        tileGrid.displayAnchor?.removeFromParent()
                        tileGrid.destroy()
                    }

                    removeAnchorWithName(for: arView, name: "ScullAnchor")
                    removeAnchorWithName(for: arView, name: "DisplayAnchor")

                    let point = CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY)
                    findRaycastResult(for: arView, point: point)

                    print("Reset complete")
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
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

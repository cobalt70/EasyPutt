//
//  ArViewContainer.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/16/25.
//  Updated by Gi Woo Kim on 7/19/26.
//
import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    typealias UIViewType = ARView
    @EnvironmentObject var arViewModel: ARViewModel
    private var updateSubscription: Cancellable?
    static var isUpdatingScreen: Bool = false
    @State var focusEntity : FocusEntity?
    
    class Coordinator: NSObject, ARSessionDelegate,ARCoachingOverlayViewDelegate  {
        var parent: ARViewContainer
        weak var arView : ARView?
        var cancellables : Set<AnyCancellable> = []
        var updateSubscription: Cancellable?
        var didPinToSuperview = false

        init(parent: ARViewContainer) {
            self.parent = parent
            self.arView = parent.arViewModel.arView
        }
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            print("session anchor didupdate")
        }
        
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
      ///      print("session frame didupdate")
            if parent.canPerformRaycast() {
                print("raycast activated ")
                parent.arViewModel.requestRaycastUpdate()
            }
            switch frame.worldMappingStatus {
                case .notAvailable:
                    print("🚨 World mapping not available")
                case .limited:
                    print("⚠️ Limited world mapping")
                case .extending:
                    print("📈 Extending world mapping")
                case .mapped:
                    print("✅ World mapping is good")
                @unknown default:
                    print("❓ Unknown mapping status")
                }
            //arViewModel에서 tracker.state값을 바꿔서 tracker 위치조정을할때 사용했었음. 속도문제가 좀 있어서별도로분리
//            if  let result = parent.arViewModel.arRaycastResult{
//               parent.updateTrackingState(parent.focusEntity, with: result)
//           }
           
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("Session failed: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("Session was interrupted")
//            session.pause()
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("Session interruption ended")
//                        if let configuration = session.configuration {
//                                session.run(configuration) // 기존 트래킹 유지
//                            } else {
//                                print("⚠️ No previous configuration found, starting a new one.")
//                                let newConfiguration = ARWorldTrackingConfiguration()
//                                newConfiguration.planeDetection = [.horizontal ]
//                                session.run(newConfiguration, options: [])
//                            }
            
        }
        
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            switch camera.trackingState {
            case .notAvailable:
                print("Tracking not available")
            case .limited(let reason):
                print("Tracking limited: \(reason)")
            case .normal:
                print("Tracking normal")
            }
        }
        
        func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
            print("Coaching Overlay 활성화됨")
            
        }
        
        // Coaching Overlay가 비활성화될 때 호출됨
        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            print("Coaching Overlay 완료됨")
        }
        
        // 목표가 변경되었을 때 호출됨
        func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
            print("세션 리셋 요청됨")
        }

        func captureBallPosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureBallPosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.ballPosition = position
            parent.arViewModel.startCollectingTerrainSamples()
            if let arView = parent.arViewModel.arView {
                removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
                drawBallMarker(at: position, in: arView)
            }
        }

        func captureHolePosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureHolePosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.holePosition = position
            parent.arViewModel.stopCollectingTerrainSamples()
            parent.arViewModel.runRangeFinder()
            if let arView = parent.arViewModel.arView {
                drawTrajectories(
                    parent.arViewModel.rangeFinderSolutions,
                    backwardOnlySolutions: parent.arViewModel.backwardOnlySolutions,
                    in: arView
                )
                drawTerrainSampleMarkers(parent.arViewModel.terrainSamples.samples, in: arView)
                drawFlagMarker(at: position, in: arView)
            }
        }

        func subscribeToCaptureTriggers() {
            parent.arViewModel.captureBallSubject
                .sink { [weak self] in self?.captureBallPosition() }
                .store(in: &cancellables)
            parent.arViewModel.captureHoleSubject
                .sink { [weak self] in self?.captureHolePosition() }
                .store(in: &cancellables)
        }


    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> ARView {
        setupARView()
      
        context.coordinator.arView = arViewModel.arView
        arViewModel.arView?.session.delegate = context.coordinator
        context.coordinator.subscribeToCaptureTriggers()


        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.goal = .tracking
        coachingOverlay.session = arViewModel.arView?.session
        coachingOverlay.delegate = context.coordinator
        DispatchQueue.main.async {
            arViewModel.arView?.addSubview(coachingOverlay)
            
            // 오토레이아웃 제약 조건 추가
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                coachingOverlay.leadingAnchor.constraint(equalTo:  arViewModel.arView!.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo:  arViewModel.arView!.trailingAnchor),
                coachingOverlay.topAnchor.constraint(equalTo:  arViewModel.arView!.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo:  arViewModel.arView!.bottomAnchor)
            ])
        }
    //    arViewModel.arView?.debugOptions.insert(.showPhysics)
        DispatchQueue.main.async {
            guard let arView = arViewModel.arView else { return }

            print("========== ARView ==========")
            print("displayZoom =", arViewModel.displayZoom)
            print("frame       =", arView.frame)
            print("bounds      =", arView.bounds)
            print("superview   =", String(describing: arView.superview?.frame))
            print("============================")
        }
        return arViewModel.arView!
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // 코칭 오버레이(makeUIView)와 같은 방식 — 수동 frame 대입(매 업데이트마다
        // superview.bounds로 덮어쓰기)은 SwiftUI 자체 레이아웃 타이밍과 어긋나면 화면이
        // 실제 전체 화면보다 작게 굳어버릴 수 있다. Auto Layout 제약조건으로 한 번만
        // 고정해서 이후 레이아웃 변화(회전, 세이프에어리어 등)에도 항상 꽉 채우게 한다.
        guard !context.coordinator.didPinToSuperview, let parentView = uiView.superview else { return }
        uiView.translatesAutoresizingMaskIntoConstraints = false
//        NSLayoutConstraint.activate([
//            uiView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
//            uiView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
//            uiView.topAnchor.constraint(equalTo: parentView.topAnchor),
//            uiView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
//        ])
        context.coordinator.didPinToSuperview = true
        DispatchQueue.main.async {
                print("========== updateUIView ==========")
                print("frame =", uiView.frame)
                print("bounds =", uiView.bounds)
                print("super =", String(describing: uiView.superview?.bounds))
                print("===============================")
            }
    }
    
    
//     coodinator session(:didUpdate)에서  updateSubject 에서 arRayCastResult를 업데이트 하면 이것을 호출해서 tracker를 업데이트 하려고함
    
    public func updateTrackingState(_ focusEntity: FocusEntity?, with raycastResult: ARRaycastResult) {
        guard let focusEntity = focusEntity else   {return}
        guard let camera = arViewModel.arView?.session.currentFrame?.camera,
              case .normal = camera.trackingState
           
        else {
            // We should place the focus entity in front of the camera instead of on a plane.
            print("DEBUG1 \(#function): camera tracking state is not normal")
            focusEntity.putInFrontOfCamera()
            focusEntity.state = .initializing
            return
        }
        print("DEBUG2 \(#function): camera tracking state is normal")
        focusEntity.state = .tracking(raycastResult: raycastResult, camera: camera)
        
    }

    private  func setupARView() {
        guard let arView = arViewModel.arView else {
            return
        }
        arView.backgroundColor = .yellow
        arView.frame = UIScreen.main.bounds
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical ]
        //   configuration.sceneReconstruction = .mesh
        //arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        //       configuration.environmentTexturing = .automatic
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        
        configuration.frameSemantics.insert(.sceneDepth)
        
        
        arView.session.run(configuration)
        //        DispatchQueue.main.async {
        //            focusEntity = FocusEntity(on: arView, style: .colored(onColor: MaterialColorParameter.color(.blue), offColor: MaterialColorParameter.color(.yellow), nonTrackingColor: MaterialColorParameter.color(.green)))
        //        }
    }
    
    func canPerformRaycast() -> Bool {
        guard let currentFrame = arViewModel.arView?.session.currentFrame else {
            print("Camera not ready")
            return false
        }
        if currentFrame.camera.trackingState == .normal    {
            print("Camera activated")
            return true
        }
        print("Camera not activated")
        return false
    }
}


/// 두 점을 잇는 얇은 원통 하나를 만든다 — 화살촉/꼬리 장식은 없는 단순한 선분이다.
func makeTrajectorySegment(from start: simd_float3, to end: simd_float3, color: UIColor, radius: Float) -> ModelEntity {
    let length = simd_distance(start, end)
    guard length > 0.0001 else { return ModelEntity() }

    let direction = normalize(end - start)
    let cylinder = MeshResource.generateCylinder(height: length, radius: radius)
    let material = UnlitMaterial(color: color)
    let segmentEntity = ModelEntity(mesh: cylinder, materials: [material])
    segmentEntity.components.set(
        CollisionComponent(
            shapes: [],
            mode: .trigger,
            filter: CollisionFilter(group: CollisionGroups.displayGround, mask: [])
        )
    )
    segmentEntity.position = start + (direction * (length / 2.0))
    segmentEntity.transform.rotation = simd_quatf(from: simd_float3(0, 1, 0), to: direction)
    return segmentEntity
}

/// start→end 방향을 가리키는 화살표(가는 원기둥 몸통 + 원뿔 화살촉)를 만든다.
func makeArrowSegment(from start: simd_float3, to end: simd_float3, color: UIColor, radius: Float) -> ModelEntity {
    let length = simd_distance(start, end)
    guard length > 0.0001 else { return ModelEntity() }

    let direction = normalize(end - start)
    let rotation = simd_quatf(from: simd_float3(0, 1, 0), to: direction)
    let headLength = min(length * 0.4, radius * 8)
    let shaftLength = max(length - headLength, 0.0001)
    let material = UnlitMaterial(color: color)

    let parent = ModelEntity()

    let shaft = ModelEntity(mesh: .generateCylinder(height: shaftLength, radius: radius), materials: [material])
    shaft.position = start + direction * (shaftLength / 2)
    shaft.transform.rotation = rotation
    parent.addChild(shaft)

    let head = ModelEntity(mesh: .generateCone(height: headLength, radius: radius * 2.5), materials: [material])
    head.position = start + direction * (shaftLength + headLength / 2)
    head.transform.rotation = rotation
    parent.addChild(head)

    return parent
}

/// path의 인접한 점들을 선분으로 이어붙여 궤적 전체를 하나의 부모 엔티티로 만든다.
func makeTrajectoryEntity(path: [simd_float3], color: UIColor, radius: Float) -> ModelEntity {
    let trajectoryEntity = ModelEntity()
    guard path.count > 1 else { return trajectoryEntity }
    for index in 0..<(path.count - 1) {
        let segment = makeTrajectorySegment(from: path[index], to: path[index + 1], color: color, radius: radius)
        trajectoryEntity.addChild(segment)
    }
    return trajectoryEntity
}

/// 각 solution마다 중앙 경로 대신 "이 범위 안으로 치면 들어간다"는 좌/우 경계
/// 경로(boundaryAPath/boundaryBPath) 두 개만 그린다. 백워드+포워드 병용 결과는
/// 빨강/초록, 백워드 전용 결과는 파랑/주황으로 구분해서 같이 그려 두 방식을 눈으로
/// 비교할 수 있게 한다. 기존 "TrajectoryAnchor"가 있으면 먼저 지운다.
func drawTrajectories(_ solutions: [PuttSolution], backwardOnlySolutions: [PuttSolution], in arView: ARView) {
    removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
    guard !solutions.isEmpty || !backwardOnlySolutions.isEmpty else { return }

    // removeAnchorWithName은 제거를 DispatchQueue.main.async로 미루므로, 새 앵커를
    // 여기서 동기로 추가하면 나중에 실행되는 제거 블록이 (같은 이름인) 새 앵커까지
    // 지워버린다. 추가도 async로 미루면 main 큐의 FIFO 순서상 제거가 먼저, 추가가
    // 나중에 실행되는 것이 보장된다.
    DispatchQueue.main.async {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "TrajectoryAnchor"

        // 백+포워드 선을 백워드 전용보다 살짝 두껍게(1px 정도) 그려서 구분이 잘 되게 한다.
        for solution in solutions {
            let aEntity = makeTrajectoryEntity(path: solution.boundaryAPath, color: .systemRed, radius: 0.003)
            anchor.addChild(aEntity)
            let bEntity = makeTrajectoryEntity(path: solution.boundaryBPath, color: .systemGreen, radius: 0.003)
            anchor.addChild(bEntity)
        }

        for solution in backwardOnlySolutions {
            let aEntity = makeTrajectoryEntity(path: solution.boundaryAPath, color: .systemBlue, radius: 0.0025)
            anchor.addChild(aEntity)
            let bEntity = makeTrajectoryEntity(path: solution.boundaryBPath, color: .systemOrange, radius: 0.0025)
            anchor.addChild(bEntity)
        }

        arView.scene.addAnchor(anchor)
    }
}

/// 수집된 지형 샘플 각각의 위치에 작은 점을 찍어, 스캔 밀도를 눈으로 확인할 수 있게 한다.
/// 기존 "TerrainSampleMarkersAnchor"가 있으면 먼저 지운다 (removeAnchorWithName과 같은
/// 이유로 제거·추가 둘 다 async로 미뤄 순서를 보장한다).
func drawTerrainSampleMarkers(_ samples: [TerrainSample], in arView: ARView) {
    removeAnchorWithName(for: arView, name: "TerrainSampleMarkersAnchor")
    guard !samples.isEmpty else { return }

    DispatchQueue.main.async {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "TerrainSampleMarkersAnchor"

        for sample in samples {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.006),
                materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
            )
            marker.position = sample.position
            anchor.addChild(marker)

            // 법선벡터를 그대로 그리면 대부분 거의 수직이라 기울기 방향이 잘 안 보인다 —
            // 중력(y) 성분을 버리고 x,z 수평면에 사영한 "내리막 방향"을 지면에 눕혀서 그린다.
            // 증폭 없이 실제 수평 성분 크기(≈기울기 정도) 그대로 — 평평하면 짧고,
            // 실제로 기울어진(또는 바닥이 아닌 물체에 맞은) 지점만 길게 나온다.
            let horizontalTilt = simd_float3(sample.normal.x, 0, sample.normal.z)
            if simd_length(horizontalTilt) > 0.0001 {
                let normalLine = makeArrowSegment(
                    from: sample.position,
                    to: sample.position + horizontalTilt,
                    color: .blue,
                    radius: 0.001
                )
                anchor.addChild(normalLine)
            }
        }

        arView.scene.addAnchor(anchor)
    }
}

/// 볼 위치에 실제 골프공 크기의 흰 공을 표시한다 (조명에 반응하는 재질이라
/// 둥근 입체감이 있다). 기존 "BallMarkerAnchor"가 있으면 먼저 지운다.
func drawBallMarker(at ballPosition: simd_float3, in arView: ARView) {
    removeAnchorWithName(for: arView, name: "BallMarkerAnchor")

    DispatchQueue.main.async {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "BallMarkerAnchor"

        let ball = ModelEntity(
            mesh: .generateSphere(radius: 0.02135),
            materials: [SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)]
        )
        ball.position = ballPosition
        anchor.addChild(ball)

        arView.scene.addAnchor(anchor)
    }
}

/// 홀 위치에 지면과 수직으로 선 폴 + 빨간 깃발을 표시한다.
/// 기존 "FlagMarkerAnchor"가 있으면 먼저 지운다.
func drawFlagMarker(at holePosition: simd_float3, in arView: ARView) {
    removeAnchorWithName(for: arView, name: "FlagMarkerAnchor")

    DispatchQueue.main.async {
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "FlagMarkerAnchor"

        // 실제 홀컵 지름(10.8cm)의 얕은 원기둥 — 지면에 살짝 파묻힌 것처럼 배치.
        let holeCup = ModelEntity(
            mesh: .generateCylinder(height: 0.001, radius: 0.054),
            materials: [UnlitMaterial(color: .systemGreen)]
        )
        holeCup.position = holePosition
        anchor.addChild(holeCup)

        let poleHeight: Float = 0.4
        let pole = ModelEntity(
            mesh: .generateCylinder(height: poleHeight, radius: 0.003),
            materials: [UnlitMaterial(color: .white)]
        )
        pole.position = holePosition + simd_float3(0, poleHeight / 2, 0)
        anchor.addChild(pole)

        // 골프장 깃발은 삼각형(페넌트) 모양이고, 폴을 관통하는 게 아니라 폴 옆면에
        // 붙어서 바깥으로 뻗어나간다 — 폴 쪽 세로변(x=0)에서 끝(tip, x=flagWidth)으로
        // 좁아지는 삼각형 메쉬를 직접 만든다.
        let flagWidth: Float = 0.1
        let flagHeight: Float = 0.06
        var flagDescriptor = MeshDescriptor(name: "flag")
        flagDescriptor.positions = MeshBuffers.Positions([
            SIMD3<Float>(0, flagHeight / 2, 0),
            SIMD3<Float>(0, -flagHeight / 2, 0),
            SIMD3<Float>(flagWidth, 0, 0)
        ])
        flagDescriptor.primitives = .triangles([0, 1, 2])

        if let flagMesh = try? MeshResource.generate(from: [flagDescriptor]) {
            let flag = ModelEntity(mesh: flagMesh, materials: [UnlitMaterial(color: .red)])
            flag.position = holePosition + simd_float3(0, poleHeight - 0.05, 0)
            // 고정된 방향의 메쉬는 옆에서 보면 두께가 0이라 사라져 보인다 —
            // BillboardComponent를 붙여서 항상 카메라를 정면으로 바라보게 한다.
            flag.components.set(BillboardComponent())
            anchor.addChild(flag)
        }

        arView.scene.addAnchor(anchor)
    }
}

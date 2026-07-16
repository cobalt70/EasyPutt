//
//  ArViewContainer.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/16/25.
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

        var golfBall : GolfBall?
        
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
      
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // 탭 이벤트 처리 로직
            guard let arView = parent.arViewModel.arView else { return }
           
            // 탭한 위치에서 raycast를 진행하고, 가상 물체와 상호작용을 처리하는 코드 작성
            let location = gesture.location(in: arView)
            
            guard let (origin, direction)  = arView.screenToWorldRay(location) else {return}
            
       //     removeEntitiesWithName(for: arView, name: "GolfBall")
        
            let virtualResults = arView.scene.raycast(
                origin: origin,
                direction: direction,
                length: 20,
                query: .all,                // 가장 가까운 충돌 객체 탐색
                mask: CollisionGroups.projectedTile,  // 'projectedTile' 그룹과만 충돌
                relativeTo: nil                 // 월드 좌표계 기준
            )
            let radius : Float = 0.02135
            let mass  : Float  = 0.04593
            let mesh = MeshResource.generateSphere(radius: radius)
            let ballEntity = ModelEntity(mesh:mesh) // 반지름 5cm 공
            ballEntity.name = "GolfBall"
            let collisionShape = ShapeResource.generateConvex(from: mesh)
            ballEntity.generateCollisionShapes(recursive:false) // 충돌 설정
        
            ballEntity.components.set(CollisionComponent(
                shapes: [collisionShape],
                mode:  .trigger,
                filter: CollisionFilter(group: CollisionGroups.golfBall, mask: []))
            )
            ballEntity.components.set(
                PhysicsBodyComponent(
                    massProperties: .init(mass: Float(mass)), // 골프공 질량 약 45.93g
                    material: PhysicsMaterialResource.generate(
                        staticFriction: 0.1,  // 정지 마찰력 (낮음)
                        dynamicFriction: 0.04, // 구를 때 마찰력
                        restitution: 0.0 // 반발 계수 (높음, 공 튀는 정도)
                    ),
                    mode: .kinematic // 물리적으로 움직이는 객체
                )
            )
            
            parent.arViewModel.previousTile = nil
            parent.arViewModel.currentTile = nil
            parent.arViewModel.ballEntity = ballEntity
            var virtualResult: CollisionCastHit? = nil
            
            for result in virtualResults{
                
                if result.entity.name !=  "ProjectedTile", let anchor = result.entity.anchor{
                    print("virtual plane fail \(result.entity.name) \(result.position) \(anchor)")
                    
                    continue
                } else {
                    virtualResult = result
                    if let anchor = result.entity.anchor   {
                        print("virtual plane success \(result.entity.name) \(result.position) \(anchor)")
                    // 추후에 엔티티 3각형 평면 안에 virtualResult가 포함되있는지 확인해봐야 할듯함.
                    }
                    
                }
                
            }
            if let virtualHit = virtualResult {
                let virtualPosition = virtualHit.position
                ballEntity.position = virtualPosition  + virtualHit.normal * 0.1// 공이 약간 위에 떠 있도록 조정
           
                
                if let anchor = virtualHit.entity.anchor {
                    anchor.addChild(ballEntity)
                   // arView.scene.addAnchor(anchor)
                } else {
                    print("virtualHit.entity.anchor is nil")
                    let anchor = AnchorEntity()
                    anchor.addChild(ballEntity)
                    arView.scene.addAnchor(anchor)
                }
                var directionFromBall = simd_float3(0,0,0)
                
                if let endPoint = parent.arViewModel.tileGrid?.endPoint , let startPoint = parent.arViewModel.tileGrid?.startPoint {
                    
                    directionFromBall = ( endPoint - ballEntity.position)
                }
                directionFromBall.y = 0
                let unitDirectionFromBall = normalize(directionFromBall)
                var initialVelocity = simd_float3(0,0,0)
                if let sideUnitVector = parent.arViewModel.tileGrid?.rotate90DegreesAroundOrigin(unitDirectionFromBall) {
                    
                    initialVelocity = normalize((directionFromBall -  sideUnitVector * parent.arViewModel.direction )) * parent.arViewModel.speed
                } else {
                    initialVelocity = unitDirectionFromBall * parent.arViewModel.speed
                }
                
                let golfBall = GolfBall(initialPosition: ballEntity.position , initialVelocity:  initialVelocity )
                
                self.golfBall = golfBall
                
                //                ballEntity.components.set(
//                    PhysicsMotionComponent(linearVelocity: initialVelocity)
//                )
             
                var lastUpdateTime: TimeInterval = 0.0
                let updateInterval: TimeInterval = 0.1 // 원하는 주기 (초)
                
                updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { event in
                    
                       lastUpdateTime += event.deltaTime
                       guard  lastUpdateTime >= updateInterval else { return }
                       lastUpdateTime = 0.0
                   
                    guard let totalCols = self.parent.arViewModel.tileGrid?.totalCols , let totalRows = self.parent.arViewModel.tileGrid?.totalRows else { return }
                    var shouldBreak : Bool = false
                    var colTest : Int = 0
                    var rowTest : Int = 0
                    var isOnTheTile : Bool = false
                    for col  in 0..<totalCols {
                        colTest = col
                        for row in 0..<totalRows {
                            rowTest = row
                            guard let tile = self.parent.arViewModel.tileGrid?.projectedTiles[col][row] else { continue }
                            print("\(#function) start:  isOnTheTile  col: \(col) row: \(row) pos:\(golfBall.position)")
                            
                            switch  tile.isOnTheTile(situatedAt: golfBall.position) {
                                
                            case .failure(let error) :
                                print("\(#function) fail: isOnTheTile \(error) col: \(col) row: \(row) pos:\(golfBall.position)")
                                isOnTheTile = false
                                continue
                            case .success(let (matchedRow, matchedCol, isUpTriangle)):

                                if  let groundNormal = isUpTriangle ? tile.projectedUpNormal : tile.projectedDnNormal {
                                    golfBall.updateFromTorque(deltaTime: 0.1 , surfaceNormal: groundNormal)
                                    
                                    let transform = Transform(
                                        scale: [1, 1, 1],
                                        rotation: golfBall.rotation,
                                        translation: golfBall.position
                                    )
                                    isOnTheTile = true
                                    shouldBreak = true
                                    print("\(#function) success: isOnTheTile col:\(matchedCol) row: \(matchedRow) up:\(isUpTriangle) normal:\(groundNormal) pos: \(golfBall.position)")
                                    ballEntity.move(to: transform, relativeTo: nil, duration: 0.0)
                                    
                                    break
                                 }
                            }
                            if shouldBreak {
                                print("\(#function) row exit \(rowTest)")
                                break
                            }
                        }
                        if shouldBreak {
                            print("\(#function) col exit \(colTest)")
                            break
                        }
                    }
                    
                    print("exit for for isOnTheTile  col \(colTest) row \(rowTest) on: \(isOnTheTile) ")
                    if golfBall.hasStopped || (rowTest == totalRows - 1  && colTest == totalCols - 1 && !isOnTheTile) {
                        print("\(#function) golfBall stopped  stopped: \(golfBall.hasStopped) on: \(isOnTheTile)")
                        self.updateSubscription?.cancel()
                        
                    }
                    
                }

                print("🎯 가상객체감지 \(#function): \(virtualPosition) \(virtualHit.entity.name)")
                
            } else {
                
                print("🎯 가상객체없음\(#function)")
            }





           }

        func captureBallPosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureBallPosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.ballPosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.startCollectingTerrainSamples()
            if let arView = parent.arViewModel.arView {
                removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
            }
        }

        func captureHolePosition() {
            guard let hit = parent.arViewModel.arRaycastResult else {
                print("captureHolePosition: raycast 결과 없음")
                return
            }
            let transform = hit.worldTransform
            parent.arViewModel.holePosition = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            parent.arViewModel.stopCollectingTerrainSamples()
            parent.arViewModel.runRangeFinder()
            if let arView = parent.arViewModel.arView {
                drawTrajectories(parent.arViewModel.rangeFinderSolutions, in: arView)
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
        arViewModel.arView?.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleTap)))
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
        return arViewModel.arView!
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        //        guard !ARViewContainer.isUpdatingScreen else {return}
        //        DispatchQueue.main.async {
        //            ARViewContainer.isUpdatingScreen = true
        //        }
        
        if let parentView = uiView.superview {
            if let arView = context.coordinator.arView {
                arView.frame = parentView.bounds
            }
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


class ButtonViewModel: ObservableObject {
    @Published var startCompleted: Bool = false
    @Published var endCompleted: Bool = false
    @Published var scanCompleted: Bool = false
    @Published var canScan: Bool = false
    // Combine을 사용하여 상태 변화 처리
    var cancellables: Set<AnyCancellable> = []
    
    init() {
        // startCompleted 또는 endCompleted가 변경될 때마다 canScan 상태 업데이트
        //$canScan // Publisher로 사용
        //         &$canScan // Binding을 사용하여 값을 쓸 수 있음
        // 같은 결과이지만 다른 표현이고 sink는 Cancellable객체를 반환함
        //        .sink { [weak self] canScan in
        //                self?.canScan = canScan
        //            }
        //            .store(in: &cancellables)  // 구독을 저장
        //        assign(to:) 메서드는 반환값이 없고, 구독을 멈출 수 있는 방법도 없음
        //assign(to:)는 단순히 값을 할당하는 방식으로 동작하기 때문에,
        //구독을 취소하거나 제어할 수 있는 Cancellable이없음
        
        $startCompleted
            .combineLatest($endCompleted)
            .map { start, end in
                return start && end  // 둘 다 true일 때만 true
            }
            .assign(to: &$canScan)
    }
    
    
    // Reset 버튼을 눌렀을 때 상태 초기화
    func reset() {
        startCompleted = false
        endCompleted = false
        scanCompleted = false
        
    }
}

/// 두 점을 잇는 얇은 원통 하나를 만든다 — Tile.swift의 createLineEntity와 같은
/// 컨벤션(원통 = 선)을 따르되, 화살촉/꼬리 장식은 없는 단순한 선분이다.
func makeTrajectorySegment(from start: simd_float3, to end: simd_float3, color: UIColor, radius: Float) -> ModelEntity {
    let length = simd_distance(start, end)
    guard length > 0.0001 else { return ModelEntity() }

    let direction = normalize(end - start)
    let cylinder = MeshResource.generateCylinder(height: length, radius: radius)
    let material = SimpleMaterial(color: color, isMetallic: false)
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

/// solutions를 모두 그리되, 첫 번째(solutions[0])만 강조색/굵은 선으로, 나머지는
/// 옅은 색/얇은 선으로 그려 구분한다. 기존 "TrajectoryAnchor"가 있으면 먼저 지운다.
func drawTrajectories(_ solutions: [PuttSolution], in arView: ARView) {
    removeAnchorWithName(for: arView, name: "TrajectoryAnchor")
    guard !solutions.isEmpty else { return }

    let anchor = AnchorEntity(world: .zero)
    anchor.name = "TrajectoryAnchor"

    for (index, solution) in solutions.enumerated() {
        let color: UIColor = index == 0 ? .systemGreen : UIColor.white.withAlphaComponent(0.4)
        let radius: Float = index == 0 ? 0.008 : 0.004
        let trajectoryEntity = makeTrajectoryEntity(path: solution.path, color: color, radius: radius)
        anchor.addChild(trajectoryEntity)
    }

    arView.scene.addAnchor(anchor)
}

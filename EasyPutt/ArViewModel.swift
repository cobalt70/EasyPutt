//
//  ArViewModel.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/1/25.
//
import ARKit
import Combine
import SwiftUI
import RealityKit
import simd
class ARViewModel : ObservableObject{
    //static var shared = ARViewModel()
    @Published var arView: ARView?
    @Published var raycastHitPosition: simd_float3?
    //raycastHitPosition이 있으면 아래 6개 점은 어디에 필요할까??
    
    @Published var realX: Float?
    @Published var realY : Float?
    @Published var realZ : Float?
    @Published var virtualX: Float?
    @Published var virtualY : Float?
    @Published var virtualZ : Float?
    
    @Published var tileGrid : TileGrid?

    let terrainSamples = TerrainSampleStore()
    var isCollectingTerrainSamples: Bool = false
    /// 화면을 N x N 격자로 나눠 raycast한다 (N = 이 값). 촘촘하게 하려면 늘린다.
    var terrainSampleGridResolution: Int = 3
    /// 격자 지점들이 화면 폭 기준 어느 범위에 퍼져 있는지 (0=왼쪽 끝, 1=오른쪽 끝).
    /// 넓히면(예: 0.05...0.95) 더 넓은 실제 폭을 커버한다.
    var terrainSampleGridSpan: ClosedRange<CGFloat> = 0.2...0.8
    /// 새 격자 수집을 실행하려면 카메라가 "지금까지의 모든 수집 지점"으로부터
    /// 최소 이만큼(미터) 떨어져 있어야 한다 — 제자리 정체나 경로가 교차할 때
    /// 중복 수집을 막는다.
    var terrainSampleMinSpacing: Float = 0.5
    private var terrainSampleCollectionCenters: [simd_float3] = []

    var tileGridOn: Bool = false
    var isRaycasting: Bool = false
    @Published var isScanning: Bool = false
    var focusEntity : FocusEntity?
    var ballEntity : ModelEntity?
    var previousTile : ModelEntity?
    var currentTile: ModelEntity?
    var previousVelocity: SIMD3<Float> = SIMD3(0, 0, 0)
    var previousPosition: SIMD3<Float> = SIMD3(0, 0, 0)
    var arRaycastResult : ARRaycastResult?
    var vrRaycastResult : CollisionCastHit?
    
    @Published var speed: Float = 2.0
    @Published var direction: Float = 0.0
    
    private var cancellables = Set<AnyCancellable>()
    private let updateSubject = PassthroughSubject<Void, Never>()
    private var updateSubscription: Cancellable?
    init() {
        self.arView = ARView(frame: .zero)
        self.tileGrid = TileGrid()
     
      

        DispatchQueue.main.async {
            if let arView =  self.arView {
                self.focusEntity = FocusEntity(on: arView, style: .colored(onColor: MaterialColorParameter.color(.blue), offColor: MaterialColorParameter.color(.yellow), nonTrackingColor: MaterialColorParameter.color(.green)))
            }
        }
        
     // 1초단위로 publish해서 ArView에서 startPoint endPoint를 update 하는데 필요할까?
        updateSubject
            .throttle(for: .seconds(0.1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard let arView = self.arView else { return }
                let center = arView.center
                (self.arRaycastResult, self.vrRaycastResult) = self.performRaycast(at :center )
                self.collectTerrainSamples()

//                if let  raycastResult  = self.arRaycastResult , let camera = arView.session.currentFrame?.camera {
//                    
//                    self.focusEntity?.state = .tracking(raycastResult: raycastResult , camera: camera)
//                }
              removeBallsBeyondDistanceFromCamera(distanceThreshold: 20.0)
                guard let hit = vrRaycastResult ,
                      isScanning == true  else {
                   return
                }
                if let entity = hit.entity as? ModelEntity {
                        // 기존 Material 가져오기
                    if  entity.name == "Tile", var modelComponent = entity.model {
                            // 새로운 색상 Material 생성
                            modelComponent.materials = [UnlitMaterial(color: .red, applyPostProcessToneMap: false)]
                            entity.model = modelComponent // 변경 적용
                        }
                    }
                var row : Int = 0
                var col : Int = 0
              
                if let gridComponent = hit.entity.components[GridComponent.self] {
                     row = gridComponent.getRow()
                     col = gridComponent.getColumn()
                    print("Tile Row: \(row), Tile Column: \(col) ")
                }
                guard let tile = self.tileGrid?.getTile(col: col, row: row) , tile.projected == false else {
                    print("original Tile is nil")
                    return
                }
               
                tile.projectedPoints.removeAll()
                
                var m : Int = 0
                
                for point in tile.points {
                   
                    let query =  ARRaycastQuery(origin: point, direction: simd_float3(0, -1, 0), allowing: .estimatedPlane, alignment: .any)
                    
                    let results =  arView.session.raycast(query)
                    print("point result \(m)th \(point) \(results.first?.worldTransform.translation ?? simd_float3(0,0,0))")
                    
                    if let firstResult = results.first {
                        
                        print("raycast success ")
                        let transform = firstResult.worldTransform
                        // 법선 벡터 (normal vector)는 변환 행렬의 세 번째 열을 사용합니다.
                        let normalVector = simd_make_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
                        
                        let projectedPoint = simd_make_float3(transform.columns.3.x, transform.columns.3.y + 0.05, transform.columns.3.z)
                        
                        print("point index \(m)th  row: \(row) col: \(col) projectedPoint:(\(projectedPoint.x) \(projectedPoint.y) \(projectedPoint.z))")
                        
                        tile.projectedPoints.append(projectedPoint)
                    } else {
                        print("index \(m) row\(row) col\(col) ")
                        print("raycast point failed. ")
                      
                    }
                    m += 1
                }
                //tileGrid.projectedTiles.flatMap { $0 }.filter { $0 != nil }.count
                if tile.projectedPoints.compactMap({$0 }).count == 4 {
                    tileGrid?.projectedTiles[col][row] = tile
                    tile.tileEntity?.removeFromParent()
                    tile.makeProjectedTileEntity()
                    
                    if let projectedTileAnchor = tileGrid?.projectedTileAnchor, let projectedTileEntity = tile.projectedTileEntity , let displayAnchor = tileGrid?.displayAnchor, let displayEntity = tile.displayEntity , tile.projected == true {
                        // projectedTileAnchor.addChild(projectedTileEntityCollection)이 미리 되있어야 하
                        print("projectedTileAnchor add child success!!")
                        
                        projectedTileAnchor.addChild(projectedTileEntity)
//                        projectedTileEntityCollection.addChild(projectedTileEntity)
//                        tileGrid?.projectedTileEntityCollection  = projectedTileEntityCollection
//                        
                         displayAnchor.addChild(displayEntity)
                    } else {
                        print("error: \(tile.projectedTileEntity) \(tileGrid?.displayAnchor) \(tile.displayEntity) \(tile.projected)")
                    }
                 
                } else {
                    tile.projected = false
                    print("raycast Tile Fail: projectedPoints count error: (row: \(tile.row!) , col: \(tile.col!)), origin: \(tile.points) , projected:\(tile.projectedPoints)")
                    return
                             }
                
            }
            .store(in: &cancellables)
        
        arView?.scene.subscribe(to: CollisionEvents.Began.self) { [weak self] event in
               
                       self?.handleCollisionBegan(event)
               
               }
               .store(in: &cancellables)
        
        arView?.scene.subscribe(to: CollisionEvents.Ended.self) { [weak self] event in
              
                       self?.handleCollisionEnded(event)
                
               }
               .store(in: &cancellables)
        
        arView?.scene.subscribe(to: SceneEvents.Update.self, on: ballEntity) { _ in
            self.trackBallVelocity()
        }.store(in: &cancellables)

    }
    
    func trackBallVelocity() {
        
     
        if let ballPhysicsBody = ballEntity?.components[PhysicsMotionComponent.self] {
            
            previousVelocity = ballPhysicsBody.linearVelocity
            previousPosition = ballEntity?.position ?? simd_float3(x:0, y:0, z:0)
            previousTile = currentTile
            print("trackBall:  \(Date()) \(ballEntity!.name) v:\(previousVelocity) p: \(previousPosition)")
        }
    }

    // ARView에서 raycast를 처리하는 메서드
    private func  handleCollisionEnded(_ event: CollisionEvents.Ended) {
        let entityA = event.entityA
        let entityB = event.entityB
        let ballEntity = (entityA.name == "GolfBall") ? entityA : entityB
        let otherEntity = (entityA.name == "GolfBall") ? entityB : entityA
        let collision = event
        

        if otherEntity.name == "ProjectedTile" {
            if let gridComponent = otherEntity.components[GridComponent.self] {
                let   row = gridComponent.getRow()
                let   col = gridComponent.getColumn()
                print("CollisionEnded Tile Row: \(row), Tile Column: \(col) \(ballEntity.name ) \(otherEntity.name)")
            }
        }
    }
    private func handleCollisionBegan(_ event: CollisionEvents.Began) {
        let entityA = event.entityA
        let entityB = event.entityB
        let ballEntity = (entityA.name == "GolfBall") ? entityA : entityB
        let otherEntity = (entityA.name == "GolfBall") ? entityB : entityA
        let collision = event
        let contacts = collision.contacts
        
        if otherEntity.name == "ProjectedTile" {
            if let gridComponent = otherEntity.components[GridComponent.self] {
                let   row = gridComponent.getRow()
                let   col = gridComponent.getColumn()
                print("CollisionBegan Tile Row: \(row), Tile Column: \(col) \(ballEntity.name ) \(otherEntity.name) ")
            }
        }
    }

    
    func handleBallTransition(_ ballEntity: Entity) -> Float?{
        let ballPosition = ballEntity.position
        
        if let nextTileHeight = getTileHeight() {
            print("nextTileHeight success")
            return nextTileHeight
            
        } else {
             print("nextTileHeight is nil")
            return nil
        }
        
        // 공의 반지름을 고려하여 높이 보정
        //       let newHeight = nextTileHeight + ball.radius
        
        // 부드러운 이동 적용
        //      ball.move(to: Transform(translation: SIMD3(ballPosition.x, newHeight, ballPosition.z)), relativeTo: nil, duration: 0.2)
    }
    
    func getTileHeight() -> Float?{
        // previousTile currentTile
        guard let previousTile = previousTile , let currentTile = currentTile else {
            print("previousTile or currentTile is nil")
            return nil
        }
        guard let gridComponentPrev = previousTile.components[GridComponent.self] ,
              let gridComponentCurr = currentTile.components[GridComponent.self] else {
            print("gridComponent is nil")
            return nil
        }
        let rowPrev = gridComponentPrev.row
        let colPrev = gridComponentPrev.column
        let rowCurr = gridComponentCurr.row
        let colCurr = gridComponentCurr.column
        
        guard let tileGrid = self.tileGrid else {
            print("tileGrid is nil")
            return nil
        }
        print("Row: \(rowPrev) / \(rowCurr) , Column: \(colPrev) / \(colCurr)")
        var height : Float? = nil
        
        if rowCurr == rowPrev && colCurr == colPrev {
            height = ballEntity?.position.y ?? 0
            print("Direction: no Change \(ballEntity?.position.y ?? 0) \(height)")
        }
        else if rowCurr == rowPrev - 1 && colCurr == colPrev {
            
            if let tile = tileGrid.projectedTiles[colCurr][rowCurr] {
                
                height = max( tile.projectedPoints[2].y, tile.projectedPoints[3].y ) + 0.022
                
            }
            print("Direction: Down \(ballEntity?.position.y ?? 0) \(height)")
            
        } else if rowCurr == rowPrev  && colCurr == colPrev + 1  {
            
            if let tile = tileGrid.projectedTiles[colCurr][rowCurr] {
                
                height = max( tile.projectedPoints[0].y  , tile.projectedPoints[3].y) + 0.022
                
            }
            print("Direction: Right \(ballEntity?.position.y ?? 0) \(height)")
        } else if rowCurr == rowPrev + 1 && colCurr == colPrev  {
            
            if let tile = tileGrid.projectedTiles[colCurr][rowCurr] {
                print("hit rowcurr = rowprev +1")
                height = max( tile.projectedPoints[0].y  , tile.projectedPoints[1].y) + 0.022
                print("hit rowcurr = rowprev + 1 \(height) ")
            }
            print("Direction: UP \(ballEntity?.position.y ?? 0) \(height) ")
        }
        else if rowCurr == rowPrev  && colCurr == colPrev - 1  {
            
            if let tile = tileGrid.projectedTiles[colCurr][rowCurr] {
                
                height = max( tile.projectedPoints[1].y  , tile.projectedPoints[2].y) + 0.022
                
            }
            print("Direction: Left \(ballEntity?.position.y ?? 0) \(height)")
        }
        else {
            print("나중에 대각선 움직임 반영")
            height = ballEntity?.position.y ?? 0 + 0.02
            height = nil
        }
        return height
    }
    
    
    
    func requestRaycastUpdate() {
        updateSubject.send()
    }

    func startCollectingTerrainSamples() {
        terrainSamples.removeAll()
        terrainSampleCollectionCenters.removeAll()
        isCollectingTerrainSamples = true
    }

    func stopCollectingTerrainSamples() {
        isCollectingTerrainSamples = false
    }

    /// 카메라가 지금까지의 모든 수집 지점으로부터 `terrainSampleMinSpacing` 이상
    /// 떨어져 있을 때만, 화면을 N x N 격자로 나눠 각 지점에서 raycast해
    /// (좌표, 법선벡터) 샘플을 모은다. `sceneReconstruction`처럼 상시 전체
    /// 환경을 재구성하지 않고, 필요한 순간에만 가볍게 여러 지점을 훑는다.
    func collectTerrainSamples() {
        guard isCollectingTerrainSamples, let arView = self.arView else { return }

        let cameraPosition = arView.cameraTransform.translation
        let tooClose = terrainSampleCollectionCenters.contains {
            simd_distance($0, cameraPosition) < terrainSampleMinSpacing
        }
        guard !tooClose else { return }
        terrainSampleCollectionCenters.append(cameraPosition)

        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0, terrainSampleGridResolution > 0 else { return }

        let fractions: [CGFloat] = (0..<terrainSampleGridResolution).map { index in
            guard terrainSampleGridResolution > 1 else { return (terrainSampleGridSpan.lowerBound + terrainSampleGridSpan.upperBound) / 2 }
            let t = CGFloat(index) / CGFloat(terrainSampleGridResolution - 1)
            return terrainSampleGridSpan.lowerBound + t * (terrainSampleGridSpan.upperBound - terrainSampleGridSpan.lowerBound)
        }

        for xFraction in fractions {
            for yFraction in fractions {
                let screenPoint = CGPoint(x: bounds.width * xFraction, y: bounds.height * yFraction)
                guard let ray = arView.screenToWorldRay(screenPoint) else { continue }
                let query = ARRaycastQuery(
                    origin: ray.origin,
                    direction: normalize(ray.direction),
                    allowing: .estimatedPlane,
                    alignment: .any
                )
                guard let hit = arView.session.raycast(query).first else { continue }
                let transform = hit.worldTransform
                let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                let normal = simd_make_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
                terrainSamples.add(position: position, normal: normal)
            }
        }
    }
    //arview.session.raycast : 현실세계 감지 arview.makeRaycastQuery 먼저 하고..
    //a arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first
    //arview.scene.raycast : arView.scene.raycast(origin: origin, direction: direction)
    
    
    func performRaycast(at screenPoint: CGPoint) -> (realResults:  ARRaycastResult?,virtualResults : CollisionCastHit?) {
        // 1️⃣ 현실 세계 감지 (ARKit)
        guard let arView  = self.arView else { return (nil,nil) }
        guard let camTransform = self.arView?.cameraTransform else {
            return(nil, nil)
        }
        let rayOrigin = arView.cameraTransform.translation // 카메라 위치
        let rayDirection = normalize(arView.screenToWorldRay(screenPoint)!.direction)
        let virtualResults = arView.scene.raycast(origin: rayOrigin, direction: rayDirection, length: 100)
        
        if let virtualHit = virtualResults.first {
            let virtualPosition = virtualHit.position
            print("🎯 가상 객체 감지: \(virtualPosition) \(virtualHit.entity.name)")
            self.virtualX = virtualPosition.x
            self.virtualY = virtualPosition.y
            self.virtualZ = virtualPosition.z
            self.raycastHitPosition = virtualPosition
            
        } else {
            self.virtualX = nil
            self.virtualY = nil
            self.virtualZ = nil
            print("🎯 가상객체없음")
        }
        
        
        let camPos = camTransform.translation
        let camDirection = camTransform.matrix.columns.2
        let direction = simd_float3(-camDirection.x, -camDirection.y, -camDirection.z)
   
        let rcQuery = ARRaycastQuery(
            origin: camPos,
            direction: direction,
            allowing: .estimatedPlane,
            alignment: .any
        )
        
        let realResults = arView.session.raycast(rcQuery)
        // Check for a result matching target
       
        
        if let realHit = realResults.first {
            let realPosition = simd_float3(realHit.worldTransform.columns.3.x,
                                           realHit.worldTransform.columns.3.y,
                                           realHit.worldTransform.columns.3.z)
            print("🌍 현실 표면 감지: \(realPosition)")
            self.raycastHitPosition = realPosition
            self.realX = realPosition.x
            self.realY = realPosition.y
            self.realZ = realPosition.z
            
        } else {
            self.realX = nil
            self.realY = nil
            self.realZ = nil
        }
        print("현실타겟\(realResults.first?.anchor) 가상이름\(virtualResults.first?.entity.name)")
        return (realResults.first, virtualResults.first)
    }
        
        
    func removeBallsBeyondDistanceFromCamera(distanceThreshold: Float) {
        // ARView에서 카메라 위치 가져오기
        guard let arView = arView else {
            return
        }
        let cameraPosition = arView.cameraTransform.translation
        // 모든 ballEntity를 확인하여 거리가 threshold 이상이면 삭제
        for anchor in arView.scene.anchors {
            for entity in anchor.children {
                // entity가 ballEntity인지 확인하고 거리 계산
                if let ballEntity = entity as? ModelEntity, ballEntity.name == "GolfBall" {
                    let distance = simd_distance(cameraPosition, ballEntity.position)
                    if distance > distanceThreshold {
                        // distance가 20m 이상이면 ballEntity 삭제
                        ballEntity.removeFromParent()
                        print("BallEntity removed due to distance: \(distance) meters")
                    }
                }
            }
        }
    }

}


extension ARView {
    func screenToWorldRay(_ point: CGPoint) -> (origin: simd_float3, direction: simd_float3)? {
        guard let raycastQuery = self.makeRaycastQuery(from: point, allowing: .estimatedPlane, alignment: .any) else {
            return nil
        }
        
        let rayOrigin = raycastQuery.origin
        let rayDirection = raycastQuery.direction

        return (rayOrigin, rayDirection)
    }
}


extension float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        self.columns.3 = SIMD4<Float>(translation, 1.0)
    }
}


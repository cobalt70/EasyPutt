//
//  Tile.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/24/25.
//

import simd
import SwiftUI
import RealityKit
import ARKit
import Combine


struct GridComponent: Component,Codable{
    var row: Int
    var column: Int
    
    func getRow() -> Int {
        return row
    }
    
    func getColumn() -> Int {
        return column
    }
}


@Observable
class Tile  {
    var parent : TileGrid? = nil
    var bottomLeft: simd_float3? = nil
    var bottomRight: simd_float3? = nil
    var topRight: simd_float3? = nil
    var topLeft: simd_float3? = nil
    var center: simd_float3? = nil
    
    //나중에
    var projectedUpNormal: simd_float3? = nil
    var projectedDnNormal: simd_float3? = nil
    var row: Int?
    var col: Int?
    
    var tileEntity : ModelEntity? = nil
    var projectedTileEntity : ModelEntity? = nil
    var displayEntity  : ModelEntity? = nil
    var projected: Bool = false
    
    var smoothedProjectedTileEntity : ModelEntity? = nil
    var smoothedDisplayEntity  : ModelEntity? = nil
    var smoothedProjected: Bool = false
    var smoothedProjectedUpNormal: simd_float3? = nil
    var smoothedProjectedDnNormal: simd_float3? = nil
    
    
    
    // 옵셔널이 아닌 simd_float3 배열로 선언
    var points: [simd_float3] {
        // 옵셔널이 아닌 값을 반환하려면 nil이 아닌 값만 포함하도록 처리
        var pointsArray: [simd_float3] = []
        
        if let bottomLeft = self.bottomLeft {
            pointsArray.append(bottomLeft)
        }
        if let bottomRight = self.bottomRight {
            pointsArray.append(bottomRight)
        }
        if let topRight = self.topRight {
            pointsArray.append(topRight)
        }
        if let topLeft = self.topLeft {
            pointsArray.append(topLeft)
        }
        
        return pointsArray
    }
    
    var projectedPoints: [simd_float3] = []
    var smoothedPoints: [simd_float3] = [.zero, .zero, .zero, .zero]
    
    var rightPadding: [simd_float3] = []
    var upPadding: [simd_float3] = []
    var junctionPadding : [simd_float3] = []
    
    var rightPaddingEntity : ModelEntity? = nil
    var upPaddingEntity : ModelEntity? = nil
    var junctionPaddingEntity : ModelEntity? = nil
    
    var smoothedRightPaddingEntity : ModelEntity? = nil
    var smoothedUpPaddingEntity : ModelEntity? = nil
    var smoothedJunctionPaddingEntity : ModelEntity? = nil
    
    init (parent : TileGrid? = nil, row: Int?, col: Int?,bottomLeft: simd_float3?, bottomRight : simd_float3? , topRight :simd_float3?, topLeft: simd_float3?) {
        if let parent = parent {
            self.parent = parent
        }
        if let row = row {
            self.row = row
        }
        if let col = col {
            self.col = col
        }
        if let bottomLeft = bottomLeft {
            self.bottomLeft = bottomLeft
        }
        if let bottomRight = bottomRight {
            self.bottomRight = bottomRight
        }
        if let topRight = topRight {
            self.topRight = topRight
        }
        if let topLeft = topLeft {
            self.topLeft = topLeft
        }
        
        makeTileEntity()
    }
    
    init (parent : TileGrid? = nil, row: Int?, col: Int?, position: [simd_float3?]) {
        if let parent = parent {
            self.parent = parent
        }
        if let row = row {
            self.row = row
        }
        if let col = col {
            self.col = col
        }
        guard  position.count >= 4  else {
            print("4 points requred to make a tile")
            return }
        
        if let bottomLeft = position[0] {
            self.bottomLeft = bottomLeft
        }
        if let bottomRight = position[1] {
            self.bottomRight = bottomRight
        }
        if let topRight = position[2] {
            self.topRight = topRight
        }
        if let topLeft = position[3] {
            self.topLeft = topLeft
        }
        
        if let center = center {
            self.center = center
        }
        
        makeTileEntity()
    }
    
    func makeTileEntity() {
        
        guard  let bottomLeft = self.bottomLeft , let bottomRight = self.bottomRight , let topRight = self.topRight , let topLeft = self.topLeft  else {
            print("4 points requred for making plane")
            return }
        
        var points : [simd_float3] = []
        points = [bottomLeft, bottomRight, topRight, topLeft]
        
        print("\(#function) points: \(points)")
        var meshDescriptor : MeshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(points)
        
        let indices :  [UInt32] = [
            0, 1, 2,
            2, 3, 0
        ]
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            let mesh = try  MeshResource.generate(from:[meshDescriptor])
            
            print("Mesh generated successfully: \(mesh )")
            
            let meshEntity =  ModelEntity(mesh: mesh)
            self.tileEntity = meshEntity
            self.tileEntity?.name =  "Tile"
            
            meshEntity.generateCollisionShapes(recursive: false)
            
            var material = UnlitMaterial(color: .yellow )
            
            material.faceCulling = .none
            meshEntity.model?.materials = [material]
            
            meshEntity.components.set(
                PhysicsBodyComponent(
                    massProperties: .default, // 잔디는 고정된 물리 속성 사용
                    material: PhysicsMaterialResource.generate(
                        staticFriction: 0.00,  // 잔디의 정지 마찰력 (낮음, 공이 잘 구름)
                        dynamicFriction: 0.00, // 구를 때 마찰력
                        restitution: 0.0// 낮은 반발 계수 (공이 튕기지 않도록 설정)
                    ),
                    mode:.static // 잔디는 움직이지 않는 고정된 표면
                )
            )
            
            if let row = row, let col = col {
                let gridComponent = GridComponent(row: row, column: col)
                meshEntity.components.set(gridComponent)
                
            }
            
        } catch{
            print("mesh error \(error)")
        }
    }
    enum TileLookupError: Error {
        case pointsNotReady
        case outOfBounds
        case vectorIsZero
        case MathError
        
    }
    func isOnTheTile( situatedAt point: simd_float3) -> Result<(row: Int, col: Int, isUpTriangle: Bool ), TileLookupError> {
        
        if case .success(let isUpTriagle) = isOnTheMainTile(situatedAt : point) {
            return .success((row: row!, col: col!, isUpTriangle: isUpTriagle))
        }else if case .success(let isUpTriangle) = isOnTheUpTile(situatedAt : point) {
            return .success((row: row!, col: col!, isUpTriangle: true))
        }else if case .success(let isUpTriangle) =  isOnTheJunctionTile(situatedAt : point){
            return .success((row: row!, col: col!, isUpTriangle: true))
        }else if case .success(let isUpTriangle) =  isOnTheRightTile(situatedAt : point){
            return .success((row: row!, col: col!, isUpTriangle: false))
        }else {
            print("ball is not on The Tile")
            return .failure(.outOfBounds)
        
        }
 
    }
    
    func isOnTheMainTile(situatedAt point: simd_float3) -> Result<Bool, TileLookupError> {
        guard let bottomLeft = self.bottomLeft, let bottomRight = self.bottomRight , let topRight = self.topRight, let topLeft = self.topLeft else {
            print("\(#function) pointsNotReady error")
            return .failure(.pointsNotReady)
        }
        
        var w0 : Float =  0
        var w1 : Float =  0
        var w2 : Float =  0
        var w3 : Float =  0
        var isOn : Bool = false
        var isUpTriangle : Bool = false
        let p  = simd_float3(point.x, 0, point.z) - simd_float3(bottomLeft.x, 0, bottomLeft.z)
        let v0 = bottomRight - bottomLeft
        let v1 = topRight  - bottomLeft
        let v2 = topLeft   - bottomLeft
        guard simd_length(v0) > 0.0001,
              simd_length(v1) > 0.0001,
              simd_length(v2) > 0.0001,
              simd_length(p) > 0.0001 else {
            return .failure(.vectorIsZero)
        }
        
        //v0 = 1 - 0
        //v1 = 2 - 0
        //v2 = 3 - 0
        //p = p - 0
        
        switch solveWeights(p: p, v0: v0, v1: v1) {
        case .success(let (wx, wy)):
            w0 = wx
            w1 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        switch solveWeights(p: p, v0: v1, v1: v2) {
        case .success(let (wx, wy)):
            w2 = wx
            w3 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        
        
        
        if w0 + w1 <= 1 && w0 >= 0 && w1 >= 0 {
            isOn = true
            isUpTriangle = false        }
        if w2 + w3 <= 1 && w2 >= 0 && w3 >= 0 {
            isOn = true
            isUpTriangle = true
        }
        
        if isOn {
            return .success(isUpTriangle)
        } else {
            return .failure(.outOfBounds)
        }
    }
    
//    var rightPadding: [simd_float3] = []
//    var upPadding: [simd_float3] = []
//    var junctionPadding : [simd_float3] = []
    
    func isOnTheRightTile(situatedAt point: simd_float3) -> Result<Bool, TileLookupError> {
        
        guard rightPadding.count == 4 else {
            print("rightPadding is not ready")
            return .failure(.pointsNotReady)
        }
        
        let bottomLeft = self.rightPadding[0]
        let bottomRight = self.rightPadding[1]
        let topRight = self.rightPadding[2]
        let topLeft = self.rightPadding[3]
        
        var w0 : Float =  0
        var w1 : Float =  0
        var w2 : Float =  0
        var w3 : Float =  0
        var isOn : Bool = false
        var isUpTriangle : Bool = false
        let p  = simd_float3(point.x, 0, point.z) - simd_float3(bottomLeft.x, 0, bottomLeft.z)
        let v0 = bottomRight - bottomLeft
        let v1 = topRight  - bottomLeft
        let v2 = topLeft   - bottomLeft
        guard simd_length(v0) > 0.0001,
              simd_length(v1) > 0.0001,
              simd_length(v2) > 0.0001,
              simd_length(p) > 0.0001 else {
            return .failure(.vectorIsZero)
        }
        
        //v0 = 1 - 0
        //v1 = 2 - 0
        //v2 = 3 - 0
        //p = p - 0
        
        switch solveWeights(p: p, v0: v0, v1: v1) {
        case .success(let (wx, wy)):
            w0 = wx
            w1 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        switch solveWeights(p: p, v0: v1, v1: v2) {
        case .success(let (wx, wy)):
            w2 = wx
            w3 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        
        
        
        if w0 + w1 <= 1 && w0 >= 0 && w1 >= 0 {
            isOn = true
            isUpTriangle = false        }
        if w2 + w3 <= 1 && w2 >= 0 && w3 >= 0 {
            isOn = true
            isUpTriangle = true
        }
        
        if isOn {
            return .success(isUpTriangle)
        } else {
            return .failure(.outOfBounds)
        }
        
        
    }
    
    func isOnTheJunctionTile(situatedAt point: simd_float3)->Result<Bool, TileLookupError>{
        guard junctionPadding.count == 4 else {
            print("junctionPadding is not ready")
            return .failure(.pointsNotReady)
        }
        
        let bottomLeft = self.junctionPadding[0]
        let bottomRight = self.junctionPadding[1]
        let topRight = self.junctionPadding[2]
        let topLeft = self.junctionPadding[3]
        
        var w0 : Float =  0
        var w1 : Float =  0
        var w2 : Float =  0
        var w3 : Float =  0
        var isOn : Bool = false
        var isUpTriangle : Bool = false
        let p  = simd_float3(point.x, 0, point.z) - simd_float3(bottomLeft.x, 0, bottomLeft.z)
        let v0 = bottomRight - bottomLeft
        let v1 = topRight  - bottomLeft
        let v2 = topLeft   - bottomLeft
        guard simd_length(v0) > 0.0001,
              simd_length(v1) > 0.0001,
              simd_length(v2) > 0.0001,
              simd_length(p) > 0.0001 else {
            return .failure(.vectorIsZero)
        }
        
        //v0 = 1 - 0
        //v1 = 2 - 0
        //v2 = 3 - 0
        //p = p - 0
        
        switch solveWeights(p: p, v0: v0, v1: v1) {
        case .success(let (wx, wy)):
            w0 = wx
            w1 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        switch solveWeights(p: p, v0: v1, v1: v2) {
        case .success(let (wx, wy)):
            w2 = wx
            w3 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        if w0 + w1 <= 1 && w0 >= 0 && w1 >= 0 {
            isOn = true
            isUpTriangle = false        }
        if w2 + w3 <= 1 && w2 >= 0 && w3 >= 0 {
            isOn = true
            isUpTriangle = true
        }
        
        if isOn {
            return .success(isUpTriangle)
        } else {
            return .failure(.outOfBounds)
        }
        
    }
    
    func isOnTheUpTile(situatedAt point: simd_float3) ->Result<Bool, TileLookupError>{
        
        guard upPadding.count == 4 else {
            print("upPadding is not ready")
            return .failure(.pointsNotReady)
        }
        
        let bottomLeft = self.upPadding[0]
        let bottomRight = self.upPadding[1]
        let topRight = self.upPadding[2]
        let topLeft = self.upPadding[3]
        
        var w0 : Float =  0
        var w1 : Float =  0
        var w2 : Float =  0
        var w3 : Float =  0
        var isOn : Bool = false
        var isUpTriangle : Bool = false
        let p  = simd_float3(point.x, 0, point.z) - simd_float3(bottomLeft.x, 0, bottomLeft.z)
        let v0 = bottomRight - bottomLeft
        let v1 = topRight  - bottomLeft
        let v2 = topLeft   - bottomLeft
        guard simd_length(v0) > 0.0001,
              simd_length(v1) > 0.0001,
              simd_length(v2) > 0.0001,
              simd_length(p) > 0.0001 else {
            return .failure(.vectorIsZero)
        }
        
        //v0 = 1 - 0
        //v1 = 2 - 0
        //v2 = 3 - 0
        //p = p - 0
        
        switch solveWeights(p: p, v0: v0, v1: v1) {
        case .success(let (wx, wy)):
            w0 = wx
            w1 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        switch solveWeights(p: p, v0: v1, v1: v2) {
        case .success(let (wx, wy)):
            w2 = wx
            w3 = wy
        case .failure(let error) :
            print("Singular Matrix Error: \(error)")
            return .failure(.MathError)
            
        }
        if w0 + w1 <= 1 && w0 >= 0 && w1 >= 0 {
            isOn = true
            isUpTriangle = false        }
        if w2 + w3 <= 1 && w2 >= 0 && w3 >= 0 {
            isOn = true
            isUpTriangle = true
        }
        
        if isOn {
            return .success(isUpTriangle)
        } else {
            return .failure(.outOfBounds)
        }
         
    }
    
    
    
    
    
    // 입력: p, v0, v1, v2
    // 목적: p = w0 * v0 + w1 * v1
    enum TriangleSolveError: Error {
        case singularMatrix
    }
    func solveWeights(p: simd_float3, v0: simd_float3, v1: simd_float3) -> Result<(Float, Float) ,TriangleSolveError> {
        let a = simd_float2(v0.x, v0.z)
        let b = simd_float2(v1.x, v1.z)
        let p2D = simd_float2(p.x, p.z)
        
        // 2x2 선형 시스템
        let mat = float2x2(columns: (a, b))
        let det = simd_determinant(mat)
        
        guard abs(det) > 1e-6 else {
            return .failure(.singularMatrix)
        }
        let inv = mat.inverse
        
        let w = inv * p2D
        return .success((w.x, w.y))
    }

    func makeProjectedTileEntity() {
        
        
        if let meshEntity = makeProjectedMeshEntity(points: self.projectedPoints , color: .green) {
            self.projectedTileEntity = meshEntity
            self.projectedTileEntity?.name =  "ProjectedTile"
            self.projected = true
        } else {
            print("\(#function) failed to make projected tile entity ")
        }
        
        let centerDown = (projectedPoints[0] + projectedPoints[1] + projectedPoints[2]) / 3
        let normalDownTriangle = normalize(cross(simd_float3(projectedPoints[1] - projectedPoints[0]) , simd_float3(projectedPoints[2] - projectedPoints[1])))
        self.projectedDnNormal = normalDownTriangle
        
        let centerUp = (projectedPoints[2] + projectedPoints[3] + projectedPoints[0]) / 3
        let normalUpTriangle = normalize(cross( simd_float3(projectedPoints[2] - projectedPoints[0]), simd_float3(projectedPoints[3] - projectedPoints[2])))
        
        self.projectedUpNormal = normalUpTriangle
        
        let forceUpTriangle = simd_float3(normalUpTriangle.x , 0 , normalUpTriangle.z)
        let forceDownTriangle = simd_float3(normalDownTriangle.x , 0 , normalDownTriangle.z)
        
        let displayEntity = ModelEntity()
        
        let upLineEntity = createLineEntity(from: centerUp, to: (centerUp + forceUpTriangle), color: .magenta)
        let dnLineEntity = createLineEntity(from: centerDown, to: (centerDown + forceDownTriangle), color: .cyan)
        
        
        let displayCollisionGroupFilter = CollisionFilter(group: CollisionGroups.displayGround, mask: [])
        
        upLineEntity.generateCollisionShapes(recursive: true)
        upLineEntity.components.set(
            CollisionComponent(
                shapes: [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        dnLineEntity.generateCollisionShapes(recursive: true)
        dnLineEntity.components.set(
            CollisionComponent(
                shapes:  [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        
        displayEntity.addChild(upLineEntity)
        displayEntity.addChild(dnLineEntity)
        displayEntity.name = "DisplayEntity"
        
        self.displayEntity =  displayEntity
        displayEntity.generateCollisionShapes(recursive: true)
        displayEntity.components.set(
            CollisionComponent(
                shapes: displayEntity.collision?.shapes ?? [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        if let row = row, let col = col {
            let gridComponent = GridComponent(row: row, column: col)
            self.projectedTileEntity?.components.set(gridComponent)
        }
        
    }
    
    func makeSmoothedProjectedTileEntity() {
        
        
        if let meshEntity = makeProjectedMeshEntity(points: self.smoothedPoints , color: .systemMint) {
            self.smoothedProjectedTileEntity = meshEntity
            self.smoothedProjectedTileEntity?.name =  "ProjectedTile"
            print("\(#function) smoothedProjectedTile Successfully")
        } else {
            print("\(#function) failed to make smmothed projected tile entity ")
        }
        
        let centerDown = (smoothedPoints[0] + smoothedPoints[1] + smoothedPoints[2]) / 3
        let normalDownTriangle = normalize(cross(simd_float3(smoothedPoints[1] - smoothedPoints[0]) , simd_float3(smoothedPoints[2] - smoothedPoints[1])))
        
        self.smoothedProjectedDnNormal = normalDownTriangle
        
        let centerUp = (smoothedPoints[2] + smoothedPoints[3] + smoothedPoints[0]) / 3
        let normalUpTriangle = normalize(cross( simd_float3(smoothedPoints[2] - smoothedPoints[0]), simd_float3(smoothedPoints[3] - smoothedPoints[2])))
        self.smoothedProjectedUpNormal = normalUpTriangle
        
        
        let forceUpTriangle = simd_float3(normalUpTriangle.x , 0 , normalUpTriangle.z)
        let forceDownTriangle = simd_float3(normalDownTriangle.x , 0 , normalDownTriangle.z)
        
        let displayEntity = ModelEntity()
        
        let upLineEntity = createLineEntity(from: centerUp, to: (centerUp + forceUpTriangle), color: .magenta)
        let dnLineEntity = createLineEntity(from: centerDown, to: (centerDown + forceDownTriangle), color: .cyan)
        
        
        let displayCollisionGroupFilter = CollisionFilter(group: CollisionGroups.displayGround, mask: [])
        
        upLineEntity.generateCollisionShapes(recursive: true)
        upLineEntity.components.set(
            CollisionComponent(
                shapes: [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        dnLineEntity.generateCollisionShapes(recursive: true)
        dnLineEntity.components.set(
            CollisionComponent(
                shapes:  [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        
        displayEntity.addChild(upLineEntity)
        displayEntity.addChild(dnLineEntity)
        displayEntity.name = "DisplayEntity"
        
        self.smoothedDisplayEntity =  displayEntity
        displayEntity.generateCollisionShapes(recursive: true)
        displayEntity.components.set(
            CollisionComponent(
                shapes: displayEntity.collision?.shapes ?? [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        if let row = row, let col = col {
            let gridComponent = GridComponent(row: row, column: col)
            self.smoothedProjectedTileEntity?.components.set(gridComponent)
            print("\(#function) row: \(row), col: \(col) success")
        }
        
    }
    
    func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor) -> ModelEntity {
        let length = simd_distance(start, end)  // 두 점 사이 거리
        let direction = normalize(end - start) // 방향 벡터
        
        let displayCollisionGroupFilter = CollisionFilter(group: CollisionGroups.displayGround, mask: [])
        print("vector length \(length)")
        // Cylinder로 선 만들기 (반지름이 매우 작은 원기둥)
        let cylinder = MeshResource.generateCylinder(height: length, radius: 0.01)
        let material = SimpleMaterial(color: color, isMetallic: false)
        
        let sphereEntity = ModelEntity(
            mesh: .generateSphere(radius: 0.01),
            materials: [SimpleMaterial(color: .yellow, isMetallic: false)]
        )
        
        sphereEntity.position = simd_float3(x:0, y: -length / 2 , z:0)
        
        let lineEntity = ModelEntity(mesh: cylinder, materials: [material])
        
        let cornEntity = ModelEntity(
            mesh:.generateCone(height: 0.02, radius: 0.02)
            , materials: [SimpleMaterial(color: color, isMetallic: false)])
        
        cornEntity.position = simd_float3(x:0,  y: length/2 , z: 0)
        cornEntity.generateCollisionShapes(recursive: false)
        cornEntity.components.set(
            CollisionComponent(
                shapes:  [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        sphereEntity.generateCollisionShapes(recursive: false)
        sphereEntity.components.set(
            CollisionComponent(
                shapes: [],
                mode: .trigger, // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        
        
        
        lineEntity.addChild(cornEntity)
        lineEntity.addChild(sphereEntity)
        lineEntity.generateCollisionShapes(recursive: true)
        lineEntity.components.set(
            CollisionComponent(
                shapes:  [],
                mode: .trigger ,// 충돌 감지만 하고 물리적 영향을 주지 않음
                filter: displayCollisionGroupFilter
            )
        )
        lineEntity.position = start  + (direction * (length / 2.0))
        let rotation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: direction)
        lineEntity.transform.rotation *= rotation
        
        
        
        return lineEntity
    }
    
    func makeRightPadding()->Bool {
        if let projectedTileEntity = self.projectedTileEntity,  let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if col + 1 < totalCols, let rightTile = parent.projectedTiles[col + 1][row] {
                rightPadding = [projectedPoints[1] , rightTile.projectedPoints[0] , rightTile.projectedPoints[3], projectedPoints[2] ]
                
                if  let rightPaddingEntity =  makeProjectedMeshEntity( points: rightPadding, color: .orange) {
                    
                    self.rightPaddingEntity = rightPaddingEntity
                    
                    //                    projectedTileEntity.addChild(rightPaddingEntity)
                    print("rightPadding added successfully")
                    return true
                } else {
                    print("rightPaddingEntity is nil ")
                    return false
                }
                
            } else {
                print("index Out Of Range rightPaddingEntity")
                return false
            }
        } else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
    }
    func makeUpPadding()-> Bool {
        if let projectedTileEntity = self.projectedTileEntity, let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if row + 1 < totalRows, let upTile = parent.projectedTiles[col][row +  1 ] {
                upPadding = [self.projectedPoints[3] , self.projectedPoints[2],  upTile.projectedPoints[1] , upTile.projectedPoints[0] ]
                
                if  let upPaddingEntity =  makeProjectedMeshEntity( points: upPadding, color: .orange) {
                    //  병렬적으로 놓을 생각임.
                    self.upPaddingEntity = upPaddingEntity
                    //                    projectedTileEntity.addChild(upPaddingEntity)
                    print("upPadding added")
                    return true
                } else {
                    print("upPaddingEntity is nil    ")
                    return false
                }
                
            } else {
                print("index Out Of Range upPaddingEntity")
                return false
                
            }
        }else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
        
    }
    func makeJunctionPadding() -> Bool {
        if let projectedTileEntity = self.projectedTileEntity, let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if row + 1 < totalRows, col + 1 < totalCols,
               let rightTile = parent.projectedTiles[col + 1][row],
               let upRightTile = parent.projectedTiles[col + 1 ][row +  1 ],
               let upTile = parent.projectedTiles[col][row +  1 ]
            {
                
                junctionPadding = [self.projectedPoints[2] , rightTile.projectedPoints[3],  upRightTile.projectedPoints[0] , upTile.projectedPoints[1] ]
                
                if  let junctionPaddingEntity =  makeProjectedMeshEntity( points: junctionPadding, color: .orange) {
                    // projectedTileEntity과 병렬적으로 놓을 생각임.
                    self.junctionPaddingEntity = junctionPaddingEntity
                    //                    projectedTileEntity.addChild(junctionPaddingEntity)
                    print("junctionPadding added")
                    return true
                } else {
                    print("junctionPaddingEntity is nil    ")
                    return false
                }
                
            } else {
                print("index Out Of Range junctionPaddingEntity")
                return false
            }
        }
        else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
        
    }
    
    
    /// 일단 working 하는지 보고 나중에 소스코드 정리..
    ///
    func makeSmoothedRightPadding()->Bool {
        if let projectedTileEntity = self.smoothedProjectedTileEntity,  let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if col < totalCols - 1, let rightTile = parent.projectedTiles[col + 1][row] {
                rightPadding = [smoothedPoints[1] , rightTile.smoothedPoints[0] , rightTile.smoothedPoints[3], smoothedPoints[2] ]
                
                if  let rightPaddingEntity =  makeProjectedMeshEntity( points: rightPadding, color: .orange) {
                    
                    self.rightPaddingEntity = rightPaddingEntity
                    
                    projectedTileEntity.addChild(rightPaddingEntity)
                    print("rightPadding added")
                    return true
                } else {
                    print("rightPaddingEntity is nil ")
                    return false
                }
                
            } else {
                print("index Out Of Range rightPaddingEntity")
                return false
            }
        } else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
    }
    func makeSmoothedUpPadding()-> Bool {
        if let projectedTileEntity = self.smoothedProjectedTileEntity, let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if row  < totalRows - 1, let upTile = parent.projectedTiles[col][row +  1 ] {
                upPadding = [self.smoothedPoints[3] , self.smoothedPoints[2],  upTile.smoothedPoints[1] , upTile.smoothedPoints[0] ]
                
                if  let upPaddingEntity =  makeProjectedMeshEntity( points: upPadding, color: .orange) {
                    
                    self.upPaddingEntity = upPaddingEntity
                    projectedTileEntity.addChild(upPaddingEntity)
                    print("upPadding added")
                    return true
                } else {
                    print("upPaddingEntity is nil    ")
                    return false
                }
                
            } else {
                print("index Out Of Range upPaddingEntity")
                return false
                
            }
        }else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
        
    }
    func makeSmoothedJunctionPadding() -> Bool {
        if let projectedTileEntity = self.smoothedProjectedTileEntity, let row = self.row, let col =  self.col, let parent = self.parent, let totalRows = parent.totalRows , let totalCols = parent.totalCols {
            if row  < totalRows - 1 , col + 1 < totalCols - 1,
               let rightTile = parent.projectedTiles[col + 1 ][row],
               let upRightTile = parent.projectedTiles[col + 1 ][row +  1 ],
               let upTile = parent.projectedTiles[col][row +  1 ]
            {
                
                junctionPadding = [self.smoothedPoints[2] , rightTile.smoothedPoints[3],  upRightTile.smoothedPoints[0] , upTile.smoothedPoints[1] ]
                
                if  let junctionPaddingEntity =  makeProjectedMeshEntity( points: junctionPadding, color: .orange) {
                    
                    self.junctionPaddingEntity = junctionPaddingEntity
                    projectedTileEntity.addChild(junctionPaddingEntity)
                    print("junctionPadding added")
                    return true
                } else {
                    print("junctionPaddingEntity is nil    ")
                    return false
                }
                
            } else {
                print("index Out Of Range junctionPaddingEntity")
                return false
            }
        }
        else {
            print("nil error")
            print("\(String(describing: self.tileEntity)) \(String(describing: self.row)) \(String(describing: self.col)) \(String(describing: self.parent))")
            return false
        }
        
    }
    func makeProjectedMeshEntity( points: [simd_float3], color: UIColor = .yellow) -> ModelEntity? {
        var meshDescriptor : MeshDescriptor = MeshDescriptor()
        //무조건 4점
        guard points.count ==  4 else {
            print("4 points required to make a projected mesh")
            return nil }
        
        meshDescriptor.positions = MeshBuffers.Positions(points)
        
        let indices :  [UInt32] = [
            0, 1, 2,
            2, 3, 0
        ]
        meshDescriptor.primitives = .triangles(indices)
        
        do {
            let mesh = try  MeshResource.generate(from:[meshDescriptor])
            print("\(#function) projected Mesh generated successfully: \(mesh)")
            
            let meshEntity =  ModelEntity(mesh: mesh)
            let collisionShape = ShapeResource.generateConvex(from: mesh)
            meshEntity.generateCollisionShapes(recursive: false)
            
            let projectedTileCollisionFilter = CollisionFilter(group: CollisionGroups.projectedTile, mask:[CollisionGroups.golfBall])
            meshEntity.components.set(CollisionComponent(
                shapes:  [collisionShape],
                mode:.colliding,
                filter: CollisionFilter(group: CollisionGroups.projectedTile, mask:  [CollisionGroups.golfBall])))
            
            meshEntity.components.set(
                PhysicsBodyComponent(
                    massProperties: .default, // 잔디는 고정된 물리 속성 사용
                    material: PhysicsMaterialResource.generate(
                        staticFriction: 0.1,  // 잔디의 정지 마찰력 (낮음, 공이 잘 구름)
                        dynamicFriction: 0.05, // 구를 때 마찰력
                        restitution: 0.0// 낮은 반발 계수 (공이 튕기지 않도록 설정)
                    ),
                    mode: .static // 잔디는 움직이지 않는 고정된 표면
                )
            )
            
            var material = UnlitMaterial(color: color)
            
            material.faceCulling = .none
            meshEntity.model?.materials = [material]
            if let row = row, let col = col {
                let gridComponent = GridComponent(row: row, column: col)
                meshEntity.components.set(gridComponent)
            }
            
            return meshEntity
            
        } catch{
            print("mesh error \(error)")
            return nil
        }
        
    }
    
}
/// 타일 그리드를 관리하는 class


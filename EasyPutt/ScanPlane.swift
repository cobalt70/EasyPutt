//
//  LoadImage.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/28/25.
//
import RealityKit
import SwiftUI
import ARKit




//4개로 했다가 센터도 추가 5개의 점을 받아서 사각형 평면을 생성하는 함수
func createPlane(from points: [simd_float3?] ,color:UIColor) async -> ModelEntity? {
    guard points.count >= 4 else { return nil }
    // 평면을 생성하는 ModelEntity (이전 로직에서 확장 가능)
    let planeEntity = await ModelEntity()
    
    // 1cm 크기의 노란색 점(구) 생성
    let sphereMesh = await MeshResource.generateSphere(radius: 0.01)
    var color : UIColor = color
    
    if points.count < 5 {
        color = .red
    }
    for point in points {
        
        guard let point = point else {continue}
        let sphereEntity = await ModelEntity(mesh: sphereMesh)
        
        DispatchQueue.main.async{
            let material = SimpleMaterial(color: color, roughness: 0.1, isMetallic: true)
            sphereEntity.model =  ModelComponent(mesh: sphereMesh, materials: [material])
            sphereEntity.position = point
            sphereEntity.name = "sphere"
            planeEntity.name = "plane"
        }
        
        await planeEntity.addChild(sphereEntity) // 구를 planeEntity에 추가
    }
    
    return planeEntity
}

func placePlaneInARView(arView: ARView, points: [SIMD3<Float>?] , color: UIColor) async {
    guard points.count >= 4 else {return}
    
    guard let planeEntity =  await createPlane(from: points , color: color) else { return }
    // ARSession에서 AnchorEntity를 생성하여 3D 공간의 중심에 배치
    let anchorEntity = await AnchorEntity() // 중심점을 기준으로 배치
    await MainActor.run {
        anchorEntity.name = "SpherePlane"
        print("Anchor Position \(String(describing: AnchorEntity.position))")
        anchorEntity.addChild(planeEntity)
        arView.scene.addAnchor(anchorEntity)
    }
}

func BuildMeshTriangstrip(arView: ARView, points: [SIMD3<Float>?] , thickness: Float = 0.016)
async {
    guard points.count >= 4 else {
        print("Not enough points to build a mesh.")
        return
    }
    
    let pointsArray = [ points[0], points[1], points[2], points[3] ]  // 4각형을 반시계로 바꿈
    let pointsWithoutNil = pointsArray.compactMap { $0 }
    
    var meshDescriptor : MeshDescriptor = MeshDescriptor()
    meshDescriptor.positions = MeshBuffers.Positions(pointsWithoutNil)
  
    let indices :  [UInt32] = [
        0, 1, 2,  // First triangle (CCW)
        2, 3, 0   // Second triangle (CCW)
    ]
    
    let lineThickness: Float = thickness
    
    meshDescriptor.primitives = .triangles(indices)
    
    do {
        let mesh = try await MeshResource.generate(from:[meshDescriptor])
        print("Mesh generated successfully: \(mesh)")
        
        let meshEntity = await ModelEntity(mesh: mesh)
        
        await meshEntity.generateCollisionShapes(recursive: false)
        DispatchQueue.main.async {
            var material = SimpleMaterial(color: .red, isMetallic: false)
            material.triangleFillMode = .fill
            meshEntity.model?.materials = [material]
        }
        
        print("meshEntity \(await meshEntity.position)")
        
        let anchorEntity = await AnchorEntity()
        await anchorEntity.addChild(meshEntity)
        
        await arView.scene.addAnchor(anchorEntity)
        print("mesh success")
    } catch{
        print("mesh error \(error)")
    }
}

// 4개의 점의 평균을 계산하여 중심점을 구하는 함수
func calculateCenter(of points: [SIMD3<Float>]) -> SIMD3<Float> {
    var sum = SIMD3<Float>(0, 0, 0)
    
    // 모든 점을 더함
    for point in points {
        sum += point
    }
    
    // 평균값을 구하여 중심점 반환
    return sum / Float(points.count)
}



func loadModel(for arView: ARView, position: simd_float3,  name : String = "") {
    // USDZ 파일 로딩
    guard let modelEntity = try? ModelEntity.loadModel(named: name ) else {
        print("Failed to load the USDZ model.")
        return
    }
    modelEntity.name = name
    // 모이 로드되면, 화면 중앙에 위치시키기 위한 raycast를 실행
    placeModelInCenter(for: arView, position: position, modelEntity: modelEntity , anchorName : "ScullAnchor" )
    // showTracker(for: arView, modelEntity: modelEntity)
}

func removeEntitiesWithName(for arView: ARView, name: String) {

        // 🔍 모든 앵커에서 특정 이름을 가진 엔티티 찾기
        let entitiesToRemove = arView.scene.anchors
            .flatMap { $0.children }
            .filter { $0.name == name }

        // 🗑️ 찾은 엔티티들 삭제
        for entity in entitiesToRemove {
            removeModelEntityAndChildren(entity) // 자식 포함 삭제
            print("✅ 삭제된 엔티티: \(entity.name)")
        }

        print("⚡ 현재 남아 있는 엔티티 목록:")
        for anchor in arView.scene.anchors {
            for entity in anchor.children {
                print(" - \(entity.name)")
            }
        }
    }


func removeAnchorWithName(for arView: ARView, name: String) {
    DispatchQueue.main.async {
        var i = 0
        let anchorsToRemove = arView.scene.anchors.filter { $0.name == name }
        for anchor in anchorsToRemove {
            if anchor.name == name {
                print("\(i) deleted anchor \(anchor.name) count: \(arView.scene.anchors.count)")
                
                for entity in anchor.children {
                    removeModelEntityAndChildren(entity)
                }
                arView.scene.removeAnchor(anchor)
                print("앵커 제거됨: \(anchor.name) ")
                
            }
            print("\(i) anchorlist \(anchor.name)")
            
            i += 1
        }
        
        for anchor in arView.scene.anchors {
            print("현재 앵커 목록: \(anchor.name )  count: \(arView.scene.anchors.count)")
        }
    }
}

func removeModelEntityAndChildren(_ entity: Entity) {
    DispatchQueue.main.async {
        for child in entity.children {
            print("deleted child entity \(child.name)")
            removeModelEntityAndChildren(child)
        }
        
        entity.removeFromParent()
        print("엔티티 및 자식들이 제거됨: \(entity.name )")
    }
}



func startSetup(arViewModel: ARViewModel) {
    // USDZ 파일 로딩
    guard let tileGrid = arViewModel.tileGrid  else {
        print("Failed to load arView")
        return
    }
    //    let center = CGPoint(x:  arView.frame.size.width / 2, y: arView.frame.size.height / 2)
    //    print("center \(center)")
    //    if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
    //        // Raycast 위치에서 모델을 배치
    //
    //        arViewModel.tileGrid?.startPoint = simd_float3(x: result.worldTransform.columns.3.x, y: result.worldTransform.columns.3.y, z:result.worldTransform.columns.3.z )
    //        print("startPoint : \(String(describing: arViewModel.tileGrid?.startPoint))")
    //    }
    //
    
    if let virtualX = arViewModel.virtualX, let virtualY = arViewModel.virtualY, let virtualZ = arViewModel.virtualZ {
        print("virtual start \(virtualX) \(virtualY) \(virtualZ)")
        tileGrid.startPoint = SIMD3<Float>(virtualX, virtualY, virtualZ)
    }
    else if let realX = arViewModel.realX , let realY = arViewModel.realY , let realZ = arViewModel.realZ {
        tileGrid.startPoint = SIMD3<Float>(realX, realY, realZ)
        print("real start \(String(describing: arViewModel.tileGrid?.startPoint))")
        
    }
  
}

func endSetup(arViewModel: ARViewModel) {
    
    guard let tileGrid = arViewModel.tileGrid  else {
        print("Failed to load tileGrid ")
        return
    }
    //    let center = CGPoint(x:  arView.frame.size.width / 2, y: arView.frame.size.height / 2)
    //    print("center \(center)")
    //    if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
    //        // Raycast 위치에서 모델을 배치
    //
    //        arViewModel.tileGrid?.startPoint = simd_float3(x: result.worldTransform.columns.3.x, y: result.worldTransform.columns.3.y, z:result.worldTransform.columns.3.z )
    //        print("startPoint : \(String(describing: arViewModel.tileGrid?.startPoint))")
    //    }
    //
    
    if let virtualX = arViewModel.virtualX, let virtualY = arViewModel.virtualY, let virtualZ = arViewModel.virtualZ {
        print("virtual end \(virtualX) \(virtualY) \(virtualZ)")
        tileGrid.endPoint = SIMD3<Float>(virtualX, virtualY, virtualZ)
    }
    else if let realX = arViewModel.realX , let realY = arViewModel.realY , let realZ = arViewModel.realZ {
        tileGrid.endPoint = SIMD3<Float>(realX, realY, realZ)
        print("real end \(String(describing: arViewModel.tileGrid?.endPoint))")
    }
    
}


// 화면 중앙에서 raycast하여 모델을 올려놓는 함수
func placeModelInCenter(for arView: ARView, modelEntity: ModelEntity , anchorName : String = "" ) {
    // 화면 중앙을 기준으로 raycast 수행
    let center = CGPoint(x: arView.frame.size.width / 2, y: arView.frame.size.height / 2)
    print("\(#function) center \(center)")
    if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
        // Raycast 위치에서 모델을 배치
        let anchor = AnchorEntity(raycastResult: result)
        print("\(#function) worldTransform \(result.worldTransform.columns.3)")
        if anchorName != "" {
            anchor.name = anchorName
        }
        modelEntity.transform.scale = SIMD3<Float>(0.5, 0.5, 0.5)
      //  modelEntity.generateCollisionShapes(recursive: false)
        modelEntity.components.set(
            CollisionComponent(
                shapes: [],
                mode: .trigger ,  // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter:  CollisionFilter(group: CollisionGroups.scull, mask: [])
            )
        )
     
        anchor.addChild(modelEntity)
        arView.scene.addAnchor(anchor)
    }
}
func placeModelInCenter(for arView: ARView, position: simd_float3 , modelEntity: ModelEntity , anchorName : String = "" ) {
    // 화면 중앙을 기준으로 raycast 수행
 
        // Raycast 위치에서 모델을 배치
        let anchor = AnchorEntity()
        if anchorName != "" {
            anchor.name = anchorName
        }
        modelEntity.transform.scale = SIMD3<Float>(0.5, 0.5, 0.5)
        modelEntity.position = position
      //  modelEntity.generateCollisionShapes(recursive: false)
        modelEntity.components.set(
            CollisionComponent(
                shapes: [],
                mode: .trigger ,  // 충돌 감지만 하고 물리적 영향을 주지 않음
                filter:  CollisionFilter(group: CollisionGroups.scull, mask: [])
            )
        )
     
        anchor.addChild(modelEntity)
        arView.scene.addAnchor(anchor)
    
}
func showTracker(for arView: ARView, modelEntity: ModelEntity){
    if let uiImage = convertSwiftUIImageToUIImage(systemName: "viewfinder"),
       let cgImage = uiImage.cgImage {

        // Create the texture resource using the new initializer (with init(image:withName:options:))
        let textureResource = try? TextureResource(image: cgImage, withName: "viewfinderTexture", options: .init(semantic: .color))

        // Check if the texture resource is successfully created
        if let textureResource = textureResource {
            
            // Create the material and apply the texture correctly using MaterialParameters
            var material = UnlitMaterial(texture: textureResource)
            material.color.tint = UIColor.yellow
            // Create the plane mesh with the desired size
            let planeMesh = MeshResource.generatePlane(width: 0.2, height: 0.2) // 20cm 크기
            let entity = ModelEntity()
            entity.model = ModelComponent(mesh: planeMesh, materials: [material])
        //    entity.generateCollisionShapes(recursive: true)
            entity.orientation = simd_quatf(angle: -.pi / 2, axis: simd_float3(1, 0, 0))
            
            entity.name = "tracker"
            
            let center = CGPoint(x: arView.frame.size.width / 2, y: arView.frame.size.height / 2)
            print("center \(center)")
            if let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first {
                // Raycast 위치에서 모델을 배치
                let anchor = AnchorEntity(world: result.worldTransform)
                print("tracker \(result.worldTransform.columns.3) \(entity.name)")
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
            }
            
        }
    }
    
}

func findRaycastResult(for arView: ARView, point: CGPoint) {
//    RealityKit > Scene > raycast()
//    @MainActor @preconcurrency
//    func raycast(
//        from startPosition: SIMD3<Float>,
//        to endPosition: SIMD3<Float>,
//        query: CollisionCastQueryType = .all,
//        mask: CollisionGroup = .all,
//        relativeTo referenceEntity: Entity? = nil
//    ) -> [CollisionCastHit]    print("point : \(point)")
    if let entity = arView.entity(at: point) {
        print(" Entity name : \(entity.name) \(entity)")
        let rayOrigin = arView.cameraTransform.translation // 카메라 위치
        let rayDirection = normalize(arView.screenToWorldRay(point)!.direction) // 화면을 3D 방향 벡터로 변환
        
        let virtualResults = arView.scene.raycast(origin: rayOrigin, direction: rayDirection, length: 20)
        
        if let virtualHit = virtualResults.first {
            let virtualPosition = virtualHit.position
            print("🎯 가상 객체 감지: \(virtualPosition)")
         
        } 
        
        if let anchor = entity.anchor {
            print("Entity Anchor will be deleted \(anchor.debugDescription) ")
            arView.scene.removeAnchor(anchor)
        } else {
            print("this entity doesn't have an anchor.")
        }
        
        
    } else {
        print("hitting the real surface")
        let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
        if let firstResult = results.first {
            let position = simd_make_float3(firstResult.worldTransform.columns.3)
            print("location \(position)")
        } else {
            print("fail to find the real surface")
        }
    }
}

private func convertSwiftUIImageToUIImage(systemName: String) -> UIImage? {
        let image = Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: 100, height: 100)
            .foregroundColor(.orange)
            .background(Color.clear)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120))
        return renderer.image { context in
            let controller = UIHostingController(rootView: image)
            controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
            controller.view.backgroundColor = .clear
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }




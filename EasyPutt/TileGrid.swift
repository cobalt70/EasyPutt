//
//  TileGrid.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/1/25.
//
import simd
import SwiftUI
import RealityKit
import ARKit
import Combine

class TileGrid : ObservableObject {
    var totalCols: Int?
    var totalRows: Int?
    var totalTileCount : Int {
        return (totalCols ?? 0) * (totalRows ?? 0)
    }
    var centerCol : Int?
    
    var tileWidth: Float  = 0.30// 타일의 가로 길이
    var tileHeight: Float = 0.30 // 타일의 세로 길이
    var padding: Float    = 0.02 //일 간 간격
    var extraRows: Int = 1
    
    var startPoint: simd_float3?
    var endPoint: simd_float3?
    
    var tileStartPoint : simd_float3?
    var tileEndPoint: simd_float3?
    
    var fixedY: Float? // 모든 타일의 y값 고정
    var liftY : Float = 0.10
    
    var direction : simd_float3?
    
    var sideUnitVector : simd_float3?
    
    var tiles: [[Tile?]] = [[]]
    var projectedTiles : [[Tile?]] =  [[]]
    var smoothedTiles : [[Tile?]] =  [[]]
    var tileAnchor : AnchorEntity? = nil
    
    var projectedTileAnchor : AnchorEntity? = nil
    var smoothedProjectedTileAnchor : AnchorEntity? = nil
    
    //   @Published var projectedTileEntityCollection: ModelEntity?
    var displayAnchor : AnchorEntity? = nil
    var smoothedDisplayAnchor : AnchorEntity? = nil
    var scanCompleted: Bool  {
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            print("scan not completed - missing totalCols or totalRows")
            return false
        }
        
        let isComplete = projectedTiles.flatMap { $0 }.filter { $0 != nil }.count == Int(totalCols * totalRows)
        
        print("scan \(isComplete ? "completed" : "not completed") - projectedTiles: \(projectedTiles.flatMap { $0 }.filter { $0 != nil }.count) / \(Int(totalCols * totalRows))")
        
        return isComplete
    }
    
    var arView : ARView?
    var cancellables = Set<AnyCancellable>()
    init() {
        
        //
        //        projectedTileEntityCollection?.components.set(
        //            CollisionComponent(
        //                shapes: projectedTileEntityCollection?.collision?.shapes ?? [],
        //                mode:  .colliding,
        //                filter: CollisionFilter(group: CollisionGroups.projectedTile, mask: [CollisionGroups.golfBall]))
        //        )
        //
        //
        //        // 뷰모델이나 클래스의 init 또는 적절한 위치에서 구독을 설정합니다.
        //        $projectedTileEntityCollection
        //            .compactMap { $0 } // nil 제거
        //            .sink { modelEntity in
        //                // projectedTileEntityCollection이 변경될 때마다 collision shape를 갱신합니다.
        //                print("$projectedTileEntityCollection SINK")
        //                modelEntity.generateCollisionShapes(recursive: true)
        //            }
        //            .store(in: &cancellables)
        //
        
    }
    func destroy(){
        projectedTiles
            .flatMap { $0 }                  // Flatten the nested array of tiles
            .compactMap { $0 }               // Filter out nil values (optional tiles)
            .forEach { $0.projectedTileEntity?.removeFromParent()
                $0.bottomLeft = nil
                $0.bottomRight = nil
                $0.topRight = nil
                $0.topLeft = nil
                $0.projectedPoints = []
                $0.projected = false
                
            }
        
        tiles
            .flatMap { $0 }                  // Flatten the nested array of tiles
            .compactMap { $0 }               // Filter out nil values (optional tiles)
            .forEach { $0.tileEntity?.removeFromParent()
                $0.bottomLeft = nil
                $0.bottomRight = nil
                $0.topRight = nil
                $0.topLeft = nil
                $0.projectedPoints = []
                $0.projected = false
            }
        if let tileAnchor = tileAnchor {
            tileAnchor.removeFromParent()
        }
        if let projectedTileAnchor = projectedTileAnchor {
            projectedTileAnchor.removeFromParent()
        }
        if let displayAnchor = displayAnchor {
            displayAnchor.removeFromParent()
        }
        
        totalCols = nil
        totalRows = nil
        centerCol = nil
        startPoint = nil
        endPoint = nil
        tileStartPoint = nil
        tileEndPoint = nil
        
        tiles = [[]]
        projectedTiles = [[]]
        
    }
    init( startPoint: simd_float3?, endPoint: simd_float3?,  tileWidth: Float?, tileHeight: Float?, padding: Float?, liftY : Float = 0.10) {
        
        if let tileWidth = tileWidth {
            self.tileWidth = tileWidth
        }
        if let tileHeight = tileHeight {
            self.tileHeight = tileHeight
        }
        if let padding = padding {
            self.padding = padding
        }
        if let startPoint = startPoint {
            self.startPoint = startPoint
            
        } else {
            print("startPoint is nil")
            return
        }
        if let endPoint = endPoint {
            self.endPoint = endPoint
            
        } else {
            print("endPoint is nil")
            return
        }
        
        if let startPoint = startPoint, let endPoint = endPoint {
            self.tileStartPoint = startPoint
            self.tileEndPoint = endPoint
            let fixedY = max(startPoint.y , endPoint.y ) + (liftY)
            self.tileStartPoint?.y = fixedY
            self.tileEndPoint?.y = fixedY
        }
        
        guard let tileStartPoint = self.tileStartPoint , let tileEndPoint = self.tileEndPoint else {
            return
        }
        if let direction = calculateUnitVector(from: tileStartPoint, to: tileStartPoint) {
            self.direction = direction
        }
        
        let distance = distance(tileStartPoint ,tileEndPoint)
        self.totalRows = Int((distance + (self.tileHeight)/2) / self.tileHeight ) + self.extraRows
        
        
        if let totalRows = self.totalRows {
            let totalCols = Int(Double(totalRows ) * 0.1) * 2 + 1
            self.centerCol = Int(totalCols / 2)
            self.totalCols = totalCols
        }
        // 단순한 평면이고 추후에 projection에 사용할 예정
        generateTiles()
        
    }
    
    
    
    func updateGrid( arView : ARView?, startPoint: simd_float3?, endPoint: simd_float3?,  tileWidth: Float? , tileHeight: Float? , padding: Float?) {
        
        if let arView = arView {
            self.arView = arView
        }
        if let tileWidth = tileWidth {
            self.tileWidth = tileWidth
        }
        if let tileHeight = tileHeight {
            self.tileHeight = tileHeight
        }
        if let padding = padding {
            self.padding = padding
        }
        if let startPoint = startPoint {
            self.startPoint = startPoint
            
        } else {
            print("startPoint is nil")
            return
        }
        if let endPoint = endPoint {
            self.endPoint = endPoint
            
        } else {
            print("endPoint is nil")
            return
        }
        
        if let startPoint = startPoint, let endPoint = endPoint {
            self.tileStartPoint = startPoint
            self.tileEndPoint = endPoint
            //            let fixedY = max(startPoint.y , endPoint.y ) + (liftY )
            //            self.tileStartPoint?.y = fixedY
            //            self.tileEndPoint?.y = fixedY
        }
        
        guard let tileStartPoint = self.tileStartPoint, let tileEndPoint = self.tileEndPoint
        else { return }
        
        if let direction = calculateUnitVector(from: tileStartPoint, to: tileStartPoint) {
            self.direction = direction
        }
        
        let distance = distance(tileStartPoint ,tileEndPoint)
        
        self.totalRows = Int((distance + (self.tileHeight)/2) / self.tileHeight ) + self.extraRows
        
        if let totalRows = self.totalRows {
            let totalCols = Int(Double(totalRows ) * 0.1) * 2 + 1
            self.centerCol = Int(totalCols / 2)
            self.totalCols = totalCols
            print("totalCols \(totalCols) totalRows \(totalRows)")
        }
        // 단순한 평면이고 추후에 projection에 사용할 예정
        tiles.removeAll()
        
        if let totalCols = self.totalCols , let totalRows  = self.totalRows{
            projectedTiles =  Array(repeating: Array(repeating: nil, count: totalRows), count: totalCols)
        }
        
        generateTiles()
        
    }
    
    // 두 점을 입력받아 Y 값을 고정하고, 단위 벡터를 계산하는 함수
    func calculateUnitVector(from startPoint: simd_float3, to endPoint: simd_float3) -> simd_float3? {
        // Y값 고정하고, X, Z 평면에서만 벡터 차이 계산
        let direction = simd_float3(endPoint.x - startPoint.x, endPoint.y - startPoint.y, endPoint.z - startPoint.z)
        
        // 벡터의 크기 계산 (X, Z만 고려)
        let lengthXZ = sqrt(direction.x * direction.x + direction.z * direction.z)
        
        // 벡터의 길이가 0이면 (두 점이 동일한 위치에 있을 경우), 단위 벡터를 계산할 수 없으므로 nil 반환
        if lengthXZ == 0 {
            return nil
        }
        
        // 단위 벡터로 정규화
        let unitVector = direction / lengthXZ
        
        return unitVector
    }
    // 수직인 경우는 z 축에대해 90도 회전하는걸로 한다.
    private func normalize(_ vector: simd_float3) -> simd_float3 {
        let length = simd_length(vector)
        return length > 0 ? vector / length : simd_float3(0, 0, 0)
    }
    
    /// 90도 반시계 방향 회전 (X-Z 평면 기준)
    // 수직인 경우는 z 축에대해 90도 회전하는걸로 한다. (Y-X)평면
    func rotate90DegreesAroundOrigin( _ vector: simd_float3) -> simd_float3 {
        
        var rotationMatrix: simd_float3x3 = simd_float3x3()
        
        print("up vector \(vector)")
        if abs( vector.y ) <=  1 {
            rotationMatrix = simd_float3x3(
                simd_float3(0,  0, -1), // X' = -Z
                simd_float3(0,  1,  0), // Y' = Y (변화 없음)
                simd_float3(1,  0,  0)  // Z' = X
            )
            return rotationMatrix * vector
            
        } else {
            let v1 =  vector
            let v2 = simd_float3(v1.x, 0, v1.z)
            let n1 = simd_cross(v2, v1 ) // y축을 중심으로 회전
            let theta: Float = .pi / 2  // 90도 회전
            
            // 벡터 회전
            let rotatedV1 = rotateVector(v1: v1, n1: n1, theta: theta)
            return rotatedV1
        }
        
        
    }
    func skewSymmetricMatrix(k: simd_float3) -> simd_float3x3 {
        return simd_float3x3(
            simd_float3(0, -k.z, k.y),
            simd_float3(k.z, 0, -k.x),
            simd_float3(-k.y, k.x, 0)
        )
    }
    
    // 벡터 v1을 n1을 중심으로 회전시키는 함수
    func rotateVector(v1: simd_float3, n1: simd_float3, theta: Float) -> simd_float3 {
        // 회전축 단위 벡터로 정규화
        let k = simd_normalize(n1)
        
        // 외적 행렬 [k]x 계산
        let kx = skewSymmetricMatrix(k: k)
        
        // k * k는 외적을 의미하므로 외적을 구하는 방법으로 계산
        let outerProduct = outerProduct(a: k, b: k)
        
        // Rodrigues' Rotation Formula에 의한 회전 행렬
        let right = (1 - cos(theta)) * outerProduct + kx * sin(theta)
        
        // 단위 행렬 생성
        let rotationMatrix = simd_float3x3(
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(0, 0, 1)
        ) * cos(theta) + right
        
        // 벡터 회전
        let rotatedVector = rotationMatrix * v1
        return rotatedVector
    }
    func outerProduct(a: simd_float3, b: simd_float3) -> simd_float3x3 {
        return simd_float3x3(
            simd_float3(a.x * b.x, a.x * b.y, a.x * b.z),
            simd_float3(a.y * b.x, a.y * b.y, a.y * b.z),
            simd_float3(a.z * b.x, a.z * b.y, a.z * b.z)
        )
    }
    
    /// 타일 생성 로직
    private func generateTiles() {
        guard let endPoint = self.tileEndPoint, let startPoint = self.tileStartPoint else {
            print("startPoint or endPoint is nil")
            return
        }
        //1m 이하일때는 수평이라고 추정함.
        if abs(endPoint.y - startPoint.y ) < 1 {
            let fixedY = max(startPoint.y , endPoint.y ) + (liftY)
            print("fixed Y in generateTiles \(fixedY)")
            self.tileStartPoint?.y = fixedY
            self.tileEndPoint?.y = fixedY
        }
        guard let endPoint = self.tileEndPoint, let startPoint = self.tileStartPoint else {
            print("startPoint or endPoint is nil")
            return
        }
        
        let directionVector = endPoint - startPoint
        let forwardUnitVector = normalize(directionVector) // 주 방향 벡터 (start → end)
        let sideUnitVector = rotate90DegreesAroundOrigin(forwardUnitVector) // 90도 회전 벡터
        self.sideUnitVector = sideUnitVector
        
        
        guard let totalCols = self.totalCols, let totalRows = self.totalRows, let centerCol = self.centerCol else {
            print("totalCols, totalRows, centerCol is nil")
            return
        }
        self.tiles.removeAll()
        print("totalCols, totalRows, centerCol \(totalCols), \(totalRows), \(centerCol)")
        for col in 0..<totalCols {
            var tileCol: [Tile] = []
            
            for row in 0..<totalRows {
                // 타일 중심 좌표 계산
                // 중심 centerCol을 가지고있어야 몇번째 column이 공과 홀컵간의 중심이 되는 컬럼인지 판별가능
                
                let center = startPoint + forwardUnitVector * Float(row) * (tileHeight + self.padding) - sideUnitVector * Float(col - centerCol) * (tileWidth + self.padding)
                // 사각형의 4개 꼭짓점 계산
                let halfWidth =  tileWidth / 2.0
                let halfHeight = tileHeight / 2.0
                
                // n1: forwardUnitVector, n2: sideUnitVector
                let h = forwardUnitVector  // 세로 방향 (forward)
                let w = -sideUnitVector    // 가로 방향 (side)
                
                // 각 꼭짓점 계산 (벡터 연산으로 개선)
                let bottomLeft = center - w * halfWidth - h * halfHeight
                let bottomRight = center + w * halfWidth - h * halfHeight
                
                let topRight = center + w * halfWidth + h * halfHeight
                let topLeft = center - w * halfWidth + h * halfHeight
                
                // 노멀 벡터 (기본적으로 위쪽을 가리킴)
                //나중에 수정
                let normalVector = simd_float3(0, 1, 0)
                
                // 타일 생성
                let tile = Tile(parent : self, row: row, col: col,
                                bottomLeft: bottomLeft,
                                bottomRight: bottomRight,topRight: topRight,topLeft: topLeft)
                print("tile init:  col: \(col) row:\(row)  points: \(tile.points) \(String(describing: tile.tileEntity?.name))")
                tileCol.append(tile)
            }
            self.tiles.append(tileCol)
        }
    }
    
    /// 특정 위치의 타일을 가져오는 함수 (안전한 접근)
    func getTile(  col: Int , row: Int) -> Tile? {
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            return nil
        }
        guard row >= 0, row < totalRows, col >= 0, col < totalCols else {
            return nil // 범위를 벗어나면 nil 반환
        }
        return tiles[col][row]
    }
    func getProjectedTile(  col: Int , row: Int) -> Tile? {
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            return nil
        }
        guard row >= 0, row < totalRows, col >= 0, col < totalCols else {
            return nil // 범위를 벗어나면 nil 반환
        }
        return projectedTiles[col][row]
    }
    func getSmoothedProjectedTile(  col: Int , row: Int) -> Tile? {
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            return nil
        }
        guard row >= 0, row < totalRows, col >= 0, col < totalCols else {
            return nil // 범위를 벗어나면 nil 반환
        }
        return smoothedTiles[col][row]
    }
    
    func show() {
        
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            print("totalCols or totalRows is nil")
            return
        }
        let tileAnchor = AnchorEntity(world:.zero)
        tileAnchor.name = "TileAnchor"
        let projectedTileAnchor = AnchorEntity(world:.zero)
        projectedTileAnchor.name = "ProjectedTileAnchor"
        let displayAnchor = AnchorEntity(world:.zero)
        displayAnchor.name = "DisplayAnchor"
        
        let projectedTileEntityCollection = ModelEntity()
        
        let smoothedDisplayAnchor = AnchorEntity(world:.zero)
        let smoothedProjectedTileAnchor = AnchorEntity(world:.zero)
        
        self.tileAnchor = tileAnchor
        self.displayAnchor = displayAnchor
        self.projectedTileAnchor = projectedTileAnchor
        self.smoothedDisplayAnchor = smoothedDisplayAnchor
        self.smoothedProjectedTileAnchor = smoothedProjectedTileAnchor
        
        //       self.projectedTileEntityCollection = projectedTileEntityCollection
        // 앵커 밑에 entity collection 추가
        //        if let projectedTileAnchor = self.projectedTileAnchor {
        //
        //            projectedTileAnchor.addChild(projectedTileEntityCollection)
        //        }
        
        for col in 0..<totalCols {
            for row in 0..<totalRows {
                guard let tile = self.getTile( col: col , row: row) else { continue }
                print("\(#function)\(col) \(row), \(String(describing: tile.tileEntity?.name ?? "")) \(tile.points) " )
                print("tileEntity : \(tile.tileEntity)")
                if let tileEntity = tile.tileEntity {
                    print("add tileEntity to tileAnchor")
                    if let tileAnchor = self.tileAnchor {
                        tileAnchor.addChild(tileEntity)
                        
                    }
                    
                }
            }
        }
        
        if let arView = self.arView, let tileAnchor = self.tileAnchor,  let displayAnchor = self.displayAnchor , let projectedTileAnchor = self.projectedTileAnchor  , let smoothedProjectedTileAnchor = self.smoothedProjectedTileAnchor , let smoothedDisplayAnchor = self.smoothedDisplayAnchor {
            
            print("anchors are added successfully")
            arView.scene.addAnchor(tileAnchor)
            arView.scene.addAnchor(displayAnchor)
            arView.scene.addAnchor(projectedTileAnchor)
            arView.scene.addAnchor(smoothedProjectedTileAnchor)
            arView.scene.addAnchor(smoothedDisplayAnchor)
        }
    }
    
    
    func makeSmoothTile(){
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            print("\(#function) totalCols or totalRows is nil")
            return
        }
        for row in 0..<totalRows  {
            for col in 0..<totalCols {
                let row = row
                let col = col
                if let currentTile = projectedTiles[col][row] ,  currentTile.projectedPoints.count == 4 {
                    if row == 0 && col == 0 {
                        for (index, point) in currentTile.projectedPoints.enumerated() {
                            var beforeSmooth : [simd_float3?] = Array(repeating: nil, count: 4)
                            if index == 0 {    //0 , 1, 2, 3
                                beforeSmooth[0] = point //
                                
                                if col > 0 , let leftTile = projectedTiles[col - 1][row] {
                                    beforeSmooth[1] = leftTile.projectedPoints[1]
                                }
                                if row > 0, col > 0 , let leftDnTile = projectedTiles[col - 1][row - 1] {
                                    beforeSmooth[2] = leftDnTile.projectedPoints[2]
                                }
                                
                                if  row > 0 , let dnTile =  projectedTiles[col ][row - 1]{
                                    beforeSmooth[2] = dnTile.projectedPoints[3]
                                }
                                let validValues = beforeSmooth.compactMap({$0})
                                let count = validValues.count
                                let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                                print("beforeSmooth index \(index) \(validValues.count)\(beforeSmooth) \(averagePosition)")
                                currentTile.smoothedPoints[0] = averagePosition
                                
                                if col > 0 , let leftTile = projectedTiles[col - 1][row] {
                                    leftTile.smoothedPoints[1] = averagePosition
                                }
                                if row > 0, col > 0 , let leftDnTile = projectedTiles[col - 1][row - 1] {
                                    leftDnTile.smoothedPoints[2] = averagePosition
                                }
                                
                                if row > 0, let dnTile =  projectedTiles[col ][row - 1]{
                                    dnTile.smoothedPoints[3] = averagePosition
                                }
                                
                            } else if index == 1 { // 1, 2, 3, 0
                                beforeSmooth[0] = point
                                
                                if  row > 0 , let dnTile =  projectedTiles[col ][row - 1]{
                                    beforeSmooth[1] = dnTile.projectedPoints[2]
                                }
                                if row > 0, col < totalCols - 1, let rightDnTile = projectedTiles[col +  1][row - 1] {
                                    beforeSmooth[2] = rightDnTile.projectedPoints[3]
                                }
                                if  col < totalCols - 1, let rightTile = projectedTiles[col + 1][row] {
                                    beforeSmooth[3] = rightTile.projectedPoints[0]
                                }
                                
                                let validValues = beforeSmooth.compactMap({$0})
                                let count = validValues.count
                                let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                                print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                                currentTile.smoothedPoints[1] = averagePosition
                                if  row > 0 , let dnTile =  projectedTiles[col][row-1]{
                                    dnTile.smoothedPoints[2] = averagePosition
                                }
                                if row > 0, col < totalCols-1, let rightDnTile = projectedTiles[col+1][row-1] {
                                    rightDnTile.smoothedPoints[3] = averagePosition
                                }
                                if  col < totalCols-1 , let rightTile = projectedTiles[col + 1][row] {
                                    rightTile.smoothedPoints[0] = averagePosition
                                }
                                
                                
                            } else if index == 2 { // 2, 3, 0 ,1
                                beforeSmooth[0] = point
                                
                                if col<totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                                    beforeSmooth[1] = rightTile.projectedPoints[3]
                                }
                                if row < totalRows-1, col < totalCols-1,let rightUpTile = projectedTiles[col+1][row+1] {
                                    beforeSmooth[2] = rightUpTile.projectedPoints[0]
                                }
                                if row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                                    beforeSmooth[3] = upTile.projectedPoints[1]
                                }
                                let validValues = beforeSmooth.compactMap({$0})
                                let count = validValues.count
                                let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                                print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                                currentTile.smoothedPoints[2] = averagePosition
                                
                                if  col < totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                                    rightTile.smoothedPoints[3] = averagePosition
                                }
                                if row < totalRows-1, col < totalCols - 1,let rightUpTile = projectedTiles[col+1][row+1] {
                                    rightUpTile.smoothedPoints[0] = averagePosition
                                }
                                if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                                    upTile.smoothedPoints[1] = averagePosition
                                }
                                
                            } else if index == 3 { // 3, 0 , 1, 2
                                beforeSmooth[0] = point
                                if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                                    beforeSmooth[1] = upTile.projectedPoints[0]
                                }
                                if row < totalRows-1, col > 0,let leftUpTile = projectedTiles[col-1][row+1] {
                                    beforeSmooth[2] = leftUpTile.projectedPoints[1]
                                }
                                if col > 0, let leftTile = projectedTiles[col - 1][row] {
                                    beforeSmooth[3] = leftTile.projectedPoints[2]
                                }
                                
                                let validValues = beforeSmooth.compactMap({$0})
                                let count = validValues.count
                                let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                                print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                                currentTile.smoothedPoints[3] = averagePosition
                                
                                if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                                    upTile.smoothedPoints[0] = averagePosition
                                }
                                if row <  totalRows-1,col > 0,let leftUpTile = projectedTiles[col-1][row+1] {
                                    leftUpTile.smoothedPoints[1] = averagePosition
                                }
                                if col > 0 , let leftTile = projectedTiles[col - 1][row] {
                                    leftTile.smoothedPoints[2] = averagePosition
                                }
                                
                                
                            } else {
                                print("\(#function) too many points")
                            }
                        }
                    }
                    else if row == 0 {
                        
                        // index 1
                        let index = 1
                        var beforeSmooth : [simd_float3?] = Array(repeating: nil, count: 4)
                        beforeSmooth[0] = currentTile.projectedPoints[1]
                        
                        if  row > 0 , let dnTile =  projectedTiles[col ][row - 1]{
                            beforeSmooth[1] = dnTile.projectedPoints[2]
                        }
                        if row > 0, col < totalCols - 1, let rightDnTile = projectedTiles[col +  1][row - 1] {
                            beforeSmooth[2] = rightDnTile.projectedPoints[3]
                        }
                        if  col < totalCols - 1, let rightTile = projectedTiles[col + 1][row] {
                            beforeSmooth[3] = rightTile.projectedPoints[0]
                        }
                        
                        let validValues = beforeSmooth.compactMap({$0})
                        let count = validValues.count
                        let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                        print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                        currentTile.smoothedPoints[1] = averagePosition
                        if  row > 0 , let dnTile =  projectedTiles[col][row-1]{
                            dnTile.smoothedPoints[2] = averagePosition
                        }
                        if row > 0, col < totalCols-1, let rightDnTile = projectedTiles[col+1][row-1] {
                            rightDnTile.smoothedPoints[3] = averagePosition
                        }
                        if  col < totalCols-1 , let rightTile = projectedTiles[col + 1][row] {
                            rightTile.smoothedPoints[0] = averagePosition
                        }
                        
                        // index 2
                        let index2 = 2
                        beforeSmooth = [nil, nil, nil, nil]
                        beforeSmooth[0] = currentTile.projectedPoints[2]
                        
                        if col<totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            beforeSmooth[1] = rightTile.projectedPoints[3]
                        }
                        if row < totalRows-1, col < totalCols-1,let rightUpTile = projectedTiles[col+1][row+1] {
                            beforeSmooth[2] = rightUpTile.projectedPoints[0]
                        }
                        if row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            beforeSmooth[3] = upTile.projectedPoints[1]
                        }
                        let validValues2 = beforeSmooth.compactMap({$0})
                        let count2 = validValues2.count
                        let averagePosition2 = validValues2.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count2),Float(count2),Float(count2))
                        print("beforeSmooth index \(index2) \(validValues2.count)\(beforeSmooth) \(averagePosition)")
                        currentTile.smoothedPoints[2] = averagePosition2
                        
                        if  col < totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            rightTile.smoothedPoints[3] = averagePosition2
                        }
                        if row < totalRows-1, col < totalCols - 1,let rightUpTile = projectedTiles[col+1][row+1] {
                            rightUpTile.smoothedPoints[0] = averagePosition2
                        }
                        if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            upTile.smoothedPoints[1] = averagePosition2
                        }
                        
                    }else if col == 0 {
                        
                        let index = 2
                        var beforeSmooth : [simd_float3?] = Array(repeating: nil, count: 4)
                        beforeSmooth[0] = currentTile.projectedPoints[2]
                        
                        if col<totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            beforeSmooth[1] = rightTile.projectedPoints[3]
                        }
                        if row < totalRows-1, col < totalCols-1,let rightUpTile = projectedTiles[col+1][row+1] {
                            beforeSmooth[2] = rightUpTile.projectedPoints[0]
                        }
                        if row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            beforeSmooth[3] = upTile.projectedPoints[1]
                        }
                        let validValues = beforeSmooth.compactMap({$0})
                        let count = validValues.count
                        let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                        print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                        currentTile.smoothedPoints[2] = averagePosition
                        
                        if  col < totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            rightTile.smoothedPoints[3] = averagePosition
                        }
                        if row < totalRows-1, col < totalCols - 1,let rightUpTile = projectedTiles[col+1][row+1] {
                            rightUpTile.smoothedPoints[0] = averagePosition
                        }
                        if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            upTile.smoothedPoints[1] = averagePosition
                        }
                        
                        //index 3
                        let index2 = 3
                        beforeSmooth = [nil,nil, nil,nil]
                        beforeSmooth[0] = currentTile.projectedPoints[3]
                        if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            beforeSmooth[1] = upTile.projectedPoints[0]
                        }
                        if row < totalRows-1, col > 0,let leftUpTile = projectedTiles[col-1][row+1] {
                            beforeSmooth[2] = leftUpTile.projectedPoints[1]
                        }
                        if col > 0, let leftTile = projectedTiles[col - 1][row] {
                            beforeSmooth[3] = leftTile.projectedPoints[2]
                        }
                        
                        let validValues2 = beforeSmooth.compactMap({$0})
                        let count2 = validValues2.count
                        let averagePosition2 = validValues2.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count2),Float(count2),Float(count2))
                        print("beforeSmooth index \(index2) \(validValues2.count)\(beforeSmooth) \(averagePosition2)")
                        currentTile.smoothedPoints[3] = averagePosition2
                        
                        if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            upTile.smoothedPoints[0] = averagePosition2
                        }
                        if row <  totalRows-1,col > 0,let leftUpTile = projectedTiles[col-1][row+1] {
                            leftUpTile.smoothedPoints[1] = averagePosition2
                        }
                        if col > 0 , let leftTile = projectedTiles[col - 1][row] {
                            leftTile.smoothedPoints[2] = averagePosition2
                        }
                        
                        
                    }
                    else {
                        //row  != 0 && col != 0
                        //index 2
                        let index = 2
                        var beforeSmooth : [simd_float3?] = Array(repeating: nil, count: 4)
                        beforeSmooth[0] = currentTile.projectedPoints[2]
                        
                        if col<totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            beforeSmooth[1] = rightTile.projectedPoints[3]
                        }
                        if row < totalRows-1, col < totalCols-1,let rightUpTile = projectedTiles[col+1][row+1] {
                            beforeSmooth[2] = rightUpTile.projectedPoints[0]
                        }
                        if row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            beforeSmooth[3] = upTile.projectedPoints[1]
                        }
                        let validValues = beforeSmooth.compactMap({$0})
                        let count = validValues.count
                        let averagePosition = validValues.reduce(simd_float3(0,0,0), +) / simd_float3(Float(count),Float(count),Float(count))
                        print("beforeSmooth index \(index) \(beforeSmooth.count)\(beforeSmooth) \(averagePosition)")
                        currentTile.smoothedPoints[2] = averagePosition
                        
                        if  col < totalCols-1, let rightTile =  projectedTiles[col+1][row]{
                            rightTile.smoothedPoints[3] = averagePosition
                        }
                        if row < totalRows-1, col < totalCols - 1,let rightUpTile = projectedTiles[col+1][row+1] {
                            rightUpTile.smoothedPoints[0] = averagePosition
                        }
                        if  row < totalRows-1, let upTile = projectedTiles[col][row+1] {
                            upTile.smoothedPoints[1] = averagePosition
                        }
                    }
                } else{
                    print("\(#function) currentTile is nil or has less than 4 points")
                }
            }
        }
    }
    
    
    
    func scanTile(col : Int ,row : Int){
        guard let tile = getTile(col: col, row: row) , tile.projected != true , let arView = arView
        else {
            print("tile is not exist and tile is already")
            return}
        
        
        let points = [tile.bottomLeft, tile.bottomRight, tile.topRight, tile.topLeft]
        self.projectedTiles.removeAll()
        for point in points {
            guard let point = point else { continue }
            let query =  ARRaycastQuery(origin: point, direction: simd_float3(0, -1, 0), allowing: .estimatedPlane, alignment: .any)
            print("query \(query)")
            let results =  arView.session.raycast(query)
            if let firstResult = results.first {
                print("raycast success ")
                let transform = firstResult.worldTransform
                // 법선 벡터 (normal vector)는 변환 행렬의 세 번째 열을 사용합니다.
                //                    let normalVector = simd_make_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
                //중복이지만 일단 Go
                //잔디 높이라던가 노이즈발생위험있어서 전체적으로 5cm 뛰움.
                let projectedPoint = simd_make_float3(transform.columns.3.x, transform.columns.3.y + 0.05, transform.columns.3.z)
                
                tile.projectedPoints.append(projectedPoint)
            } else {
                print("projection error!")
            }
            
        }
        if tile.projectedPoints.count == 4 {
            tile.projected = true
        } else {
            tile.projected = false
        }
    }
    
    func makePadding() {
        
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            print("\(#function) totalCols or totalRows is nil")
            return
        }
        print("\(#function) pass guard")
        for col in 0..<totalCols {
            for row in 0..<totalRows {
                guard let projectedTile = self.projectedTiles[col][row]  else
                {
                    print("\(#function)  \(col)  \(row) projectedtile is nil")
                    continue
                }
                
                let resultMakePadding = projectedTile.makeRightPadding()
                let resultMakeUpPadding = projectedTile.makeUpPadding()
                let resultMakeJunctionPadding = projectedTile.makeJunctionPadding()
                
                print("resultMakePadding : \(resultMakePadding) resultMakeUpPadding:\(resultMakeUpPadding) resultMakeJunctionPadding:\(resultMakeJunctionPadding)")
                
                if  let projectedTileAnchor = self.projectedTileAnchor {
                    print("add projectedtileEntity, rightPadding, upPadding, junctionPaddding to projectedTileAnchor")
                    if  let rightPaddingEntity = projectedTile.rightPaddingEntity {
                        projectedTileAnchor.addChild(rightPaddingEntity)
                    }
                    if let upPaddingEntity = projectedTile.upPaddingEntity{
                        projectedTileAnchor.addChild(upPaddingEntity)
                    }
                    if let junctionPaddingEntity = projectedTile.junctionPaddingEntity {
                        projectedTileAnchor.addChild(junctionPaddingEntity)
                    }
                    //                    if let projectedTileEntity = projectedTile.projectedTileEntity {
                    //                        projectedTileAnchor.addChild(projectedTileEntity)
                    //                    }
                }
            }
        }
        
    }
    
    func makeSmoothPadding(){
        
        guard let totalCols = self.totalCols, let totalRows = self.totalRows else {
            print("\(#function) totalCols or totalRows is nil")
            return
        }
        //projected file이 만들어진 상태에서 스무딩 좌표로 다시 좌표를 한번 더 만듬.
        makeSmoothTile()
        
        if let smoothedProjectedTileAnchor = self.smoothedProjectedTileAnchor {
            smoothedProjectedTileAnchor.children.removeAll()
        }
        print("\(#function) pass guard")
        
        for col in 0..<totalCols {
            for row in 0..<totalRows {
                guard let projectedTile = self.projectedTiles[col][row]  else
                {
                    print("\(#function)  \(col)  \(row) projectedtile is nil")
                    continue
                }
                
                print("\(#function) row: \(row)  col: \(col)  count:\(projectedTile.smoothedPoints.count) smoothed: \(projectedTile.smoothedPoints)")
                projectedTile.makeSmoothedProjectedTileEntity()
                if let smoothedProjectedTileEntity = projectedTile.smoothedProjectedTileEntity {
                    smoothedProjectedTileAnchor?.addChild(smoothedProjectedTileEntity)
                }
                
                if let smoothedDisplayEntity = projectedTile.smoothedDisplayEntity {
                    smoothedDisplayAnchor?.addChild(smoothedDisplayEntity)
                }
                //                let resultMakePadding = projectedTile.makeSmoothedRightPadding()
                //                let resultMakeUpPadding = projectedTile.makeSmoothedUpPadding()
                //                let resultMakeJunctionPadding = projectedTile.makeSmoothedJunctionPadding()
                //
                //                print("\(#function) resultMakePadding : \(resultMakePadding) resultMakeUpPadding:\(resultMakeUpPadding) resultMakeJunctionPadding:\(resultMakeJunctionPadding)")
                //                if  let projectedTileAnchor = self.smoothedProjectedTileAnchor {
                //                    print("add projectedtileEntity, rightPadding, upPadding, junctionPaddding to projectedTileAnchor")
                //                    if  let smoothedProjectedTileEntity = projectedTile.smoothedProjectedTileEntity {
                //                        projectedTileAnchor.addChild(smoothedProjectedTileEntity)
                //                    }
                //                    if  let smoothedRightPaddingEntity = projectedTile.smoothedRightPaddingEntity{
                //                        projectedTileAnchor.addChild(smoothedRightPaddingEntity)
                //                    }
                //                    if let smoothedUpPaddingEntity = projectedTile.smoothedUpPaddingEntity{
                //                        projectedTileAnchor.addChild(smoothedUpPaddingEntity)
                //                    }
                //                    if let smoothedJunctionPaddingEntity = projectedTile.smoothedJunctionPaddingEntity {
                //                        projectedTileAnchor.addChild(smoothedJunctionPaddingEntity)
                //                    }
                //                    if let projectedTileEntity = projectedTile.projectedTileEntity {
                //                        projectedTileAnchor.addChild(projectedTileEntity)
                //                    }
                //               }
            }
        }
        
    }
}



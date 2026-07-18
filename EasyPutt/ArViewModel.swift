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
import Foundation
import UIKit
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

    let terrainSamples = TerrainSampleStore()
    var isCollectingTerrainSamples: Bool = false
    /// 화면에 보여줄 3x3 조준 격자선의 칸 크기(포인트) — 순전히 시각적 가이드이며,
    /// 실제 수집 지점(화면 중앙)에는 영향을 주지 않는다.
    @Published var terrainSampleGridSpacing: Float = 60
    /// 새 수집을 실행하려면 조준 지점이 "지금까지의 모든 수집 지점"으로부터
    /// 최소 이만큼(미터) 떨어져 있어야 한다 — 제자리 정체나 경로가 교차할 때
    /// 중복 수집을 막는다. 실제로는 매 틱 gridCellMeters(격자 한 칸의 실제 거리)를
    /// 우선 쓰고, 그 값을 못 구했을 때만 이 고정값으로 대체한다.
    var terrainSampleMinSpacing: Float = 0.3
    /// 카메라에서 조준 지점까지의 거리가 이보다 가까우면 수집을 생략한다 —
    /// 너무 가까운/가파른 각도의 raycast는 노이즈가 커서 신뢰하기 어렵다.
    var terrainSampleMinCenterDistance: Float = 0.3
    private var terrainSampleCollectionCenters: [simd_float3] = []
    private var centerRaycastMarkerEntity: ModelEntity?
    private var centerRaycastMarkerAnchor: AnchorEntity?
    /// 지금 이 순간, 화면상 격자 한 칸(terrainSampleGridSpacing)이 실제 지면에서
    /// 몇 미터에 해당하는지 — 카메라 거리/각도에 따라 계속 바뀌므로 매 틱 갱신한다.
    @Published var gridCellMeters: Float?

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

    /// 지금 화면(AR 뷰)을 이미지로 캡처해 사진 앱에 저장한다.
    func saveSnapshot() {
        arView?.snapshot(saveToHDR: false) { image in
            guard let image = image else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
    }

    @Published var ballPosition: simd_float3?
    @Published var holePosition: simd_float3?
    @Published var rangeFinderSolutions: [PuttSolution] = []
    /// forward 시뮬레이션(verify/correct) 없이 백워드 추적 + 이분탐색만으로 구한 해/범위
    /// — rangeFinderSolutions(백워드+포워드 병용)와 값/속도를 비교하기 위한 두 번째 결과.
    @Published var backwardOnlySolutions: [PuttSolution] = []
    @Published var ballToHoleDistance: Float?
    /// 두 방식의 계산 소요시간(ms) — 백워드 전용이 forward 검증이 없는 만큼 더 빠를 것으로
    /// 예상되나, 실제 값으로 비교하기 위해 측정한다.
    @Published var rangeFinderElapsedMs: Double?
    @Published var backwardOnlyElapsedMs: Double?

    /// 스팀프미터 측정값(미터) — 표준 스팀프 램프 방출 속도(1.83m/s)로 굴렸을 때
    /// 이 거리만큼 가다 멈추는 그린 속도. rollingResistance = v² / (2 × stimpReading)로 환산한다.
    @Published var stimpReading: Float = 2.70
    private let stimpReleaseSpeed: Float = 1.83
    var rollingResistance: Float {
        (stimpReleaseSpeed * stimpReleaseSpeed) / (2 * stimpReading)
    }

    /// 대표(첫 번째) 솔루션의 속도를 "평지였다면 이 속도로 얼마나 갔을까"로 되돌린
    /// 거리 — 오르막/내리막 때문에 실제 거리와 체감이 달라지는 걸 보여준다.
    /// d = v² / (2 × rollingResistance), stimpReading 환산과 같은 등감속 공식의 역산.
    var adjustedDistance: Float? {
        guard let speed = rangeFinderSolutions.first?.speed else { return nil }
        return (speed * speed) / (2 * rollingResistance)
    }

    /// 볼-홀 두 점의 3D 직선거리와 높이차만으로 직접 구한 평지환산 거리 — 백워드/
    /// 포워드 풀이(rangeFinderSolutions)를 전혀 거치지 않아 볼/홀 위치만 있으면 바로
    /// 나온다. 경사가 완만하고 거의 직선에 가까운 그린에서는 adjustedDistance(실제
    /// 풀이된 speed 기반)와 비슷해야 하지만, 볼-홀 사이 지형이 오르막-내리막으로
    /// 굴곡져 있으면(중간 지형을 전혀 안 보고 양끝 높이차 하나로만 경사를 가정하므로)
    /// 그 굴곡을 반영하지 못한다.
    /// alpha: 볼→홀 3D 직선이 수평면과 이루는 경사각(양수 = 오르막).
    /// 5/7 계수는 GolfBall.updateFromTorque의 굴림 가속도 모델과 맞춘 것이고
    /// (구가 미끄러짐 없이 구를 때 위치에너지 일부가 회전운동에너지로 가는 관성 보정),
    /// rollingResistance는 GolfBall.applyRollingResistance처럼 경사와 무관하게
    /// 고정값으로 다뤄서(cos(alpha)로 깎지 않음) 실제 시뮬레이션 물리와 일치시켰다.
    var slopeAdjustedDistance: Float? {
        guard let ball = ballPosition, let hole = holePosition else { return nil }
        let distance = simd_distance(ball, hole)
        guard distance > 0.0001 else { return nil }
        let dy = hole.y - ball.y
        let alpha = asin(max(-1, min(1, dy / distance)))
        let totalDeceleration = (5.0 / 7.0) * 9.8 * sin(alpha) + rollingResistance
        // 아주 가파른 내리막이면 경사가 구름저항보다 강해 공이 멈추지 않고 계속
        // 가속되는 구조가 될 수 있다 — 이 경우 "멈추는 거리"라는 개념 자체가
        // 성립하지 않으므로 nil을 반환한다(그린 대부분은 완만해 거의 발생하지 않음).
        guard totalDeceleration > 0 else { return nil }
        return distance * totalDeceleration / rollingResistance
    }

    let captureBallSubject = PassthroughSubject<Void, Never>()
    let captureHoleSubject = PassthroughSubject<Void, Never>()

    var tileGridOn: Bool = false
    var isRaycasting: Bool = false
    var focusEntity : FocusEntity?
    var arRaycastResult : ARRaycastResult?
    var vrRaycastResult : CollisionCastHit?

    private var cancellables = Set<AnyCancellable>()
    private let updateSubject = PassthroughSubject<Void, Never>()
    private var updateSubscription: Cancellable?
    init() {
        self.arView = ARView(frame: .zero)

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
                self.updateGridCellMeters()
                self.collectTerrainSamples()
                self.updateCenterRaycastMarker()

//                if let  raycastResult  = self.arRaycastResult , let camera = arView.session.currentFrame?.camera {
//
//                    self.focusEntity?.state = .tracking(raycastResult: raycastResult , camera: camera)
//                }
            }
            .store(in: &cancellables)

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

    /// 화면 중앙을 기준으로 화면에 보이는 3x3 정사각형 격자(칸 크기 = terrainSampleGridSpacing,
    /// 포인트 단위)의 9칸 전부가 화면 안에 온전히 들어올 때만(모서리가 잘리지 않을 때만)
    /// 각 칸 중심의 (좌표, 법선벡터)를 수집한다. "조준 지점"(중앙 칸)이 마지막으로 수집한
    /// 지점들로부터 `terrainSampleMinSpacing` 이상 떨어졌을 때만 새로 수집한다.
    func collectTerrainSamples() {
        guard isCollectingTerrainSamples, let arView = self.arView else { return }
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let s = CGFloat(terrainSampleGridSpacing)
        let half = 1.5 * s
        guard cx - half >= 0, cx + half <= bounds.width, cy - half >= 0, cy + half <= bounds.height else { return }

        func groundHit(at screenPoint: CGPoint) -> (position: simd_float3, normal: simd_float3)? {
            guard let ray = arView.screenToWorldRay(screenPoint) else { return nil }
            let query = ARRaycastQuery(origin: ray.origin, direction: normalize(ray.direction), allowing: .estimatedPlane, alignment: .any)
            guard let hit = arView.session.raycast(query).first else { return nil }
            let transform = hit.worldTransform
            let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let normal = simd_make_float3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
            return (position, normal)
        }

        guard let centerHit = groundHit(at: CGPoint(x: cx, y: cy)) else { return }
        let cameraPosition = arView.cameraTransform.translation
        guard simd_distance(cameraPosition, centerHit.position) > terrainSampleMinCenterDistance else { return }

        let minSpacing = gridCellMeters ?? terrainSampleMinSpacing
        let tooClose = terrainSampleCollectionCenters.contains {
            simd_distance($0, centerHit.position) < minSpacing
        }
        guard !tooClose else { return }
        terrainSampleCollectionCenters.append(centerHit.position)

        let offsets: [CGFloat] = [-s, 0, s]
        for yOffset in offsets {
            for xOffset in offsets {
                guard let hit = groundHit(at: CGPoint(x: cx + xOffset, y: cy + yOffset)) else { continue }
                terrainSamples.add(position: hit.position, normal: hit.normal)
            }
        }
    }

    /// 지형 스캔 중(isCollectingTerrainSamples)에만 화면 중앙 raycast 결과(arRaycastResult)
    /// 위치에 작은 구체 마커를 표시한다. 9개 격자점 전부가 아니라 이 하나만 보여줘서
    /// "지금 지면을 인식하고 있다"는 최소한의 시각 피드백을 준다. 매 틱 새로 만들지 않고
    /// 엔티티 하나를 재사용해 위치만 갱신한다.
    func updateCenterRaycastMarker() {
        guard let arView = self.arView else { return }

        guard isCollectingTerrainSamples, let hit = arRaycastResult else {
            if let anchor = centerRaycastMarkerAnchor {
                // 씬 루트 앵커는 parent가 없어 removeFromParent()가 no-op이다 —
                // 반드시 scene.removeAnchor로 제거해야 한다 (ScanPlane.swift의
                // removeAnchorWithName과 동일한 패턴).
                arView.scene.removeAnchor(anchor)
                centerRaycastMarkerAnchor = nil
                centerRaycastMarkerEntity = nil
            }
            return
        }

        let transform = hit.worldTransform
        let position = simd_make_float3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)

        if centerRaycastMarkerEntity == nil {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: 0.01),
                materials: [SimpleMaterial(color: .cyan, isMetallic: false)]
            )
            let anchor = AnchorEntity(world: .zero)
            anchor.name = "CenterRaycastMarkerAnchor"
            anchor.addChild(marker)
            arView.scene.addAnchor(anchor)
            centerRaycastMarkerEntity = marker
            centerRaycastMarkerAnchor = anchor
        }
        centerRaycastMarkerEntity?.position = position
    }

    /// 화면 중앙에서 동서남북 4방향으로 격자 한 칸(terrainSampleGridSpacing)만큼 떨어진
    /// 지점들을 각각 지면에 raycast해서, 중앙까지의 실제 거리를 평균 낸다 — 폰 각도에 따라
    /// 방향별로 값이 달라질 수 있어 평균으로 대표값을 삼는다. 화면상 격자 크기가 카메라
    /// 거리/각도에 따라 실제로 몇 미터를 의미하는지 실시간으로 보여주기 위함.
    func updateGridCellMeters() {
        guard let arView = self.arView else {
            gridCellMeters = nil
            return
        }
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else {
            gridCellMeters = nil
            return
        }
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let s = CGFloat(terrainSampleGridSpacing)

        func groundPosition(at screenPoint: CGPoint) -> simd_float3? {
            guard let ray = arView.screenToWorldRay(screenPoint) else { return nil }
            let query = ARRaycastQuery(origin: ray.origin, direction: normalize(ray.direction), allowing: .estimatedPlane, alignment: .any)
            guard let hit = arView.session.raycast(query).first else { return nil }
            return simd_make_float3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
        }

        guard let center = groundPosition(at: CGPoint(x: cx, y: cy)) else {
            gridCellMeters = nil
            return
        }

        let neighbors = [
            CGPoint(x: cx + s, y: cy),
            CGPoint(x: cx - s, y: cy),
            CGPoint(x: cx, y: cy + s),
            CGPoint(x: cx, y: cy - s),
        ].compactMap { groundPosition(at: $0) }

        guard !neighbors.isEmpty else {
            gridCellMeters = nil
            return
        }
        let distances = neighbors.map { simd_distance(center, $0) }
        gridCellMeters = distances.reduce(0, +) / Float(distances.count)
    }

    func runRangeFinder() {
        guard let ball = ballPosition, let hole = holePosition else {
            print("runRangeFinder: ball 또는 hole 위치가 없음")
            return
        }
        ballToHoleDistance = simd_distance(ball, hole)
        let finder = PuttRangeFinder(terrain: terrainSamples, config: PuttRangeFinderConfig(rollingResistance: rollingResistance))

        let combinedStart = Date()
        rangeFinderSolutions = finder.findSolutions(ballPosition: ball, holePosition: hole)
        rangeFinderElapsedMs = Date().timeIntervalSince(combinedStart) * 1000

        let backwardOnlyStart = Date()
        backwardOnlySolutions = finder.findSolutionsBackwardOnly(ballPosition: ball, holePosition: hole)
        backwardOnlyElapsedMs = Date().timeIntervalSince(backwardOnlyStart) * 1000
    }

    /// 볼→홀 직선을 forward 축으로 삼는 "퍼트 좌표계"에서, 주어진 수평 방향벡터의
    /// (오른쪽, 전진) 성분을 반환한다. 세션 시작 시점에 고정되는 임의의 AR 월드축
    /// 대신, 사용자가 실제로 서서 보는 볼→홀 방향 기준으로 dir을 해석하기 위함.
    func puttRelative(_ direction: simd_float3) -> (right: Float, forward: Float)? {
        guard let ball = ballPosition, let hole = holePosition else { return nil }
        let toHole = simd_float3(hole.x - ball.x, 0, hole.z - ball.z)
        guard simd_length(toHole) > 0.0001 else { return nil }
        let forwardAxis = normalize(toHole)
        let rightAxis = simd_float3(-forwardAxis.z, 0, forwardAxis.x)
        return (right: simd_dot(direction, rightAxis), forward: simd_dot(direction, forwardAxis))
    }

    /// 초기 조준 방향을 직선으로 연장했을 때, 홀컵까지의 거리(forward)만큼 나아간
    /// 지점이 홀컵 중심에서 좌우로 몇 cm 떨어지는지를 구한다. 실제 궤적은 경사
    /// 때문에 휘어 들어가지만, 이건 "홀컵 기준 몇 cm 옆을 보고 쳐야 하는지"를
    /// 직선 근사로 직관적으로 보여주기 위한 값이다. 상한/하한 없이 계산값 그대로 반환한다.
    /// 좌우 오프셋은 수평(플레이어가 실제로 걷는 방향) 기준이라, ballToHoleDistance(3D
    /// 직선거리, 높이차 포함)가 아니라 여기서 별도로 구한 수평거리를 쓴다.
    func aimOffsetCentimeters(_ rel: (right: Float, forward: Float)) -> Float? {
        guard let ball = ballPosition, let hole = holePosition, rel.forward > 0.0001 else { return nil }
        let distance = simd_distance(simd_float3(ball.x, 0, ball.z), simd_float3(hole.x, 0, hole.z))
        let lateralMeters = distance * (rel.right / rel.forward)
        return lateralMeters * 100
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

//
//  GolfBall.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/23/25.
//
import SwiftUI
import simd
import RealityKit
// MARK: - 골프공 모델 클래스
class GolfBall: ObservableObject {
    // 위치 및 회전
    @Published var position: simd_float3
    @Published var rotation: simd_quatf
    var activeGolfBall: GolfBall?
    var activeBallEntity: ModelEntity?
    var isSimulating: Bool = false
    // 속도
    var velocity: simd_float3 = .zero
    private var angularVelocity: simd_float3 = .zero

    // 물리 속성
    private let radius: Float = 0.021
    private let mass: Float = 0.045
    private let muStatic: Float = 0.4
    private let muKinetic: Float = 0.2
    private let gravity = simd_float3(0, -9.8, 0)
    /// 구름저항(rolling resistance) 감속 계수 — 그린 속도(스팀프값)에 해당하는 튜닝 파라미터.
    var rollingResistance: Float = 0.35

    // 상태
    private var isRolling = false

    init(initialPosition: simd_float3) {
        self.position = initialPosition
        self.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }
    init(initialPosition: simd_float3, initialVelocity: simd_float3 = .zero) {
        
        self.position = initialPosition
        print("\(type(of: self)) initialVelocity \(initialVelocity)")
        self.velocity = simd_float3(initialVelocity.x , 0 , initialVelocity.z)
        self.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
    }
    var hasStopped: Bool {
        simd_length(velocity) < 0.005 &&  simd_length(angularVelocity) < 0.01
    }

    // 토크 기반 시뮬레이션 (미끄러짐 → 구름으로 전환)
    func updateFromTorque(deltaTime dt: Float, surfaceNormal n: simd_float3) {
        let gravityParallel = gravity - simd_dot(gravity, n) * n
        let accelMag = simd_length(gravityParallel) * (5.0 / 7.0)
        let acceleration: simd_float3
        if accelMag > 0.0001 {
            let accelDir = simd_normalize(gravityParallel)
            acceleration = accelDir * accelMag
        } else {
            acceleration = .zero
        }

        // 선속도 및 위치 업데이트.
        // 정방향(dt>=0)은 이제 백워드와 정확히 역연산이 맞아떨어져야 한다는 제약이 없다 —
        // forward 결과는 이제 별도로(verify()/PuttRangeFinder의 forward 검증) 다시 확인되므로,
        // 백워드가 "정방향을 정확히 되짚는 것"에 더 이상 기대지 않는다. 그래서 정방향은
        // 진입 시점 속도 기준의 정확한 운동학 공식(position += v·dt + 0.5·a·dt²)을 쓴다
        // (구름저항은 단순 상수 가속도가 아니라 위치 공식에 깔끔히 못 넣으므로 속도에만 반영).
        //
        // 역방향(dt<0)은 백워드 추적(backwardOnlySolve 등)이 여전히 그 위에서 동작하므로
        // 손대지 않는다 — 위치 갱신에 "되돌리기 전(진입 시점)" 속도를 쓰고, 속도 서브스텝
        // 순서도 뒤집어서((위치→마찰 되돌리기→가속 되돌리기) 순) 정방향 스텝의 정확한
        // 역연산을 유지한다.
        if dt >= 0 {
            let entryVelocity = velocity
            position += entryVelocity * dt + 0.5 * acceleration * dt * dt
            velocity += acceleration * dt
            applyRollingResistance(deltaTime: dt)
        } else {
            position += velocity * dt   // 되돌리기 전(진입 시점) 속도로 위치 갱신
            applyRollingResistance(deltaTime: dt)
            velocity += acceleration * dt
        }

        guard simd_length(velocity) > 0.0001 else { return }
        guard simd_length(gravityParallel) > 0.0001 else { return }

        // 토크 계산
        let normalForce = -simd_dot(gravity, n)
        let frictionForce = muKinetic * normalForce
        let frictionVec = simd_normalize(gravityParallel) * frictionForce
        let rotationAxis = simd_normalize(simd_cross(n, frictionVec))

        let torqueMag = radius * frictionForce
        let inertia = (2.0 / 5.0) * mass * pow(radius, 2)
        let angularAccel = torqueMag / inertia

        // 각속도 업데이트
        angularVelocity += rotationAxis * angularAccel * dt

        // 구름 상태 판단
        let targetAngular = simd_length(velocity) / radius
        let angularDiff = abs(simd_length(angularVelocity) - targetAngular)
        isRolling = (angularDiff < 0.01)

        if isRolling {
            angularVelocity = rotationAxis * targetAngular
        }

        // 회전 누적
        let angle = simd_length(angularVelocity) * dt
        let deltaRotation = simd_quatf(angle: angle, axis: rotationAxis)
        rotation = simd_normalize(deltaRotation * rotation)
    }

    /// 구름저항을 병진속도에 반영한다. `dt`가 음수(역방향 계산)면 자연히 반대로
    /// 작용해 속도가 늘어난다 — 별도의 "역방향" 분기 없이 동일한 식으로 양방향을 다룬다.
    private func applyRollingResistance(deltaTime dt: Float) {
        let speed = simd_length(velocity)
        guard speed > 0.0001 else {
            velocity = .zero
            return
        }
        let newSpeed = max(0, speed - rollingResistance * dt)
        velocity = simd_normalize(velocity) * newSpeed
    }

    /// 주어진 법선벡터에서 최대 경사(내리막) 방향을 수평 평면에 투영해 얻는다.
    /// 법선벡터는 (tx, 1, tz) 형태의 기울기 벡터로 해석되며, 수평 경사(tx, tz)를 추출한다.
    /// 평평한 면(tx=tz=0)에서는 경사 방향이 없으므로 `.zero`를 반환한다.
    static func steepestDescentDirection(surfaceNormal n: simd_float3) -> simd_float3 {
        let horizontalSlope = simd_float3(n.x, 0, n.z)
        let slopeLength = simd_length(horizontalSlope)
        guard slopeLength > 0.0001 else { return .zero }
        return simd_normalize(horizontalSlope)
    }
}

// MARK: - SwiftUI View (단순한 시각화 예시)
struct GolfBallView: View {
    @StateObject private var ball = GolfBall(initialPosition: [0, 0.02, 0])
    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Text("Position: \(ball.position.x, specifier: "%.2f"), \(ball.position.z, specifier: "%.2f")")
            Circle()
                .fill(Color.green)
                .frame(width: 20, height: 20)
                .offset(x: CGFloat(ball.position.x * 300), y: CGFloat(ball.position.z * 300))
        }
        .onReceive(timer) { _ in
            let groundNormal = simd_normalize(simd_float3(0.2, 1.0, 0.3)) // 예시: 경사면 법선
            ball.updateFromTorque(deltaTime: 1.0 / 60.0, surfaceNormal: groundNormal)
        }
    }
}

// MARK: - 미리보기
struct GolfBallView_Previews: PreviewProvider {
    static var previews: some View {
        GolfBallView()
    }
}

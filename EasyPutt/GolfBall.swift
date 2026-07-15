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
    // 순수 구름 가정한 업데이트
    var hasStopped: Bool {
        simd_length(velocity) < 0.001 &&  simd_length(angularVelocity) < 0.01
    }
    func update(deltaTime dt: Float, surfaceNormal n: simd_float3) {
        // 중력 분해
        let gravityParallel = gravity - simd_dot(gravity, n) * n
        let accelMag = (5.0 / 7.0) * simd_length(gravityParallel)
        let accelDir = simd_normalize(gravityParallel)
        let acceleration = accelDir * accelMag

        // 선속도 및 위치 업데이트
        velocity += acceleration * dt
        position += velocity * dt

        // 회전축 계산
        guard simd_length(velocity) > 0.0001 else { return }
        let rotationAxis = simd_normalize(simd_cross(n, velocity))

        // 각속도 벡터 = v / r
        let speed = simd_length(velocity)
        let angularSpeed = speed / radius
        angularVelocity = rotationAxis * angularSpeed
        isRolling = true

        // 회전 적용
        let angle = angularSpeed * dt
        let deltaRotation = simd_quatf(angle: angle, axis: rotationAxis)
        rotation = simd_normalize(deltaRotation * rotation)
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

        // 선속도 및 위치 업데이트
        velocity += acceleration * dt
        applyRollingResistance(deltaTime: dt)
        position += velocity * dt

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

//
//  GolfBallRollingResistanceTests.swift
//  EasyPuttTests
//
//  Created by Gi Woo Kim on 7/16/26.
//  Updated by Gi Woo Kim on 7/19/26.
//

import XCTest
import simd
@testable import EasyPutt

final class GolfBallRollingResistanceTests: XCTestCase {

    func testBallOnFlatGroundEventuallyStops() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(1.0, 0, 0))
        ball.rollingResistance = 0.5
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.05

        var stopped = false
        for _ in 0..<200 {
            ball.updateFromTorque(deltaTime: dt, surfaceNormal: flatNormal)
            if ball.hasStopped {
                stopped = true
                break
            }
        }

        XCTAssertTrue(stopped, "flat-ground ball should eventually stop under rolling resistance")
    }

    func testRollingResistanceDeceleratesTranslationalSpeed() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(1.0, 0, 0))
        ball.rollingResistance = 0.5
        let flatNormal = simd_float3(0, 1, 0)

        ball.updateFromTorque(deltaTime: 0.1, surfaceNormal: flatNormal)

        // Expected speed after one step: 1.0 - rollingResistance * dt = 1.0 - 0.05 = 0.95
        // (flat ground: gravityTangent is zero, so only rolling resistance acts.)
        XCTAssertEqual(simd_length(ball.velocity), 0.95, accuracy: 0.001)
    }

    func testSteepestDescentDirectionOnTiltedSurface() {
        // Normal tilted toward +x means the surface descends toward +x.
        let normal = simd_normalize(simd_float3(0.2, 1, 0))
        let direction = GolfBall.steepestDescentDirection(surfaceNormal: normal)

        XCTAssertGreaterThan(direction.x, 0, "descent direction should point toward +x for this tilt")
        XCTAssertEqual(direction.y, 0, accuracy: 0.001, "descent direction should be horizontal")
        XCTAssertEqual(simd_length(direction), 1.0, accuracy: 0.001)
    }

    func testSteepestDescentDirectionOnFlatSurfaceIsZero() {
        let normal = simd_float3(0, 1, 0)
        let direction = GolfBall.steepestDescentDirection(surfaceNormal: normal)
        XCTAssertEqual(simd_length(direction), 0, accuracy: 0.0001, "flat ground has no descent direction")
    }

    func testBackwardIntegrationRoundTripsOnSteepSlope() {
        // 경사가 구름저항보다 강한 경우(accelMag > rollingResistance, 여기서는 10도
        // 경사) — 이전에는 다단계 역방향 적분이 발산했다. 정방향으로 N스텝 진행한 뒤
        // 같은 스텝 수만큼 역방향으로 되돌리면, 원래 상태 근처로 복귀해야 한다.
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(0.08, 0, 0))
        ball.rollingResistance = 0.35
        let steepNormal = simd_normalize(simd_float3(tan(10 * Float.pi / 180), 1, 0))
        let dt: Float = 0.05
        let steps = 60

        let originalPosition = ball.position
        let originalVelocity = ball.velocity

        for _ in 0..<steps {
            ball.updateFromTorque(deltaTime: dt, surfaceNormal: steepNormal)
        }
        for _ in 0..<steps {
            ball.updateFromTorque(deltaTime: -dt, surfaceNormal: steepNormal)
        }

        XCTAssertEqual(ball.position.x, originalPosition.x, accuracy: 0.0001)
        XCTAssertEqual(ball.velocity.x, originalVelocity.x, accuracy: 0.0001)
    }

    // MARK: - updateForwardWithSlip (미끄럼→구름 전환, 병진에도 마찰 반영)

    func testSlipPhaseAppliesFullSlopeAccelerationNotReducedByRollingFactor() {
        // 속도를 경사 방향(x)과 수직인 z축으로 둬서, 마찰이 x축 가속에 영향을 주지
        // 않게 분리한다 — x축 가속 변화는 순수하게 "경사가속도가 5/7로 줄었는지
        // 아닌지"만 반영한다.
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(0, 0, 1.0))
        ball.rollingResistance = 0.35
        let tiltedNormal = simd_normalize(simd_float3(0.1, 1, 0))
        let dt: Float = 0.1

        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: tiltedNormal)

        let gravity: Float = 9.8
        let tiltAngle = atan(Float(0.1))
        let fullSlopeAccelX = gravity * sin(tiltAngle) * cos(tiltAngle)
        let reducedSlopeAccelX = fullSlopeAccelX * (5.0 / 7.0)

        XCTAssertGreaterThan(ball.velocity.x, reducedSlopeAccelX * dt,
            "미끄럼 구간의 경사가속도는 5/7 공식보다 커야 한다")
        XCTAssertEqual(ball.velocity.x, fullSlopeAccelX * dt, accuracy: 0.01,
            "미끄럼 구간에서는 경사가속도(gravityParallel)가 5/7로 줄지 않고 그대로 실려야 한다")
    }

    func testTransitionsFromSlipDecelerationToRollingDeceleration() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(2.0, 0, 0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.01

        let speedBeforeFirstStep = simd_length(ball.velocity)
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        let firstStepDrop = speedBeforeFirstStep - simd_length(ball.velocity)

        // 초반엔 미끄럼 상태라 muKinetic(0.2) 기준으로 감속해야 한다(0.2×9.8×dt≈0.0196) —
        // rollingResistance(0.35×dt=0.0035)보다 훨씬 크다.
        XCTAssertEqual(firstStepDrop, 0.2 * 9.8 * dt, accuracy: 0.002,
            "미끄럼 첫 스텝은 muKinetic 기준으로 감속해야 한다")

        for _ in 0..<200 {
            ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        }

        let speedBeforeLateStep = simd_length(ball.velocity)
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        let lateStepDrop = speedBeforeLateStep - simd_length(ball.velocity)

        // 충분히 지나면 순수구름으로 전환되어 rollingResistance 기준으로 감속해야 한다.
        XCTAssertEqual(lateStepDrop, ball.rollingResistance * dt, accuracy: 0.002,
            "충분한 스텝 이후에는 rollingResistance 기준(순수구름)으로 감속해야 한다")
    }

    func testRollingPhaseUsesReducedSlopeAcceleration() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(2.0, 0, 0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)
        let dt: Float = 0.01

        // 평지에서 충분히 스텝을 돌려 순수구름 상태로 전환시킨다(평지는 경사가
        // 없어서 전환 여부만 깨끗하게 만들 수 있다).
        for _ in 0..<200 {
            ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: flatNormal)
        }

        // 이제 경사면으로 바꿔서 한 스텝 — 이미 순수구름 상태이므로 5/7 공식이
        // 적용되어야 한다(testSlipPhase...와 반대 검증).
        let tiltedNormal = simd_normalize(simd_float3(0.1, 1, 0))
        let velocityXBefore = ball.velocity.x
        ball.updateForwardWithSlip(deltaTime: dt, surfaceNormal: tiltedNormal)

        let gravity: Float = 9.8
        let tiltAngle = atan(Float(0.1))
        let reducedSlopeAccelX = gravity * sin(tiltAngle) * cos(tiltAngle) * (5.0 / 7.0)
        let velocityChangeX = ball.velocity.x - velocityXBefore

        XCTAssertEqual(velocityChangeX, reducedSlopeAccelX * dt, accuracy: 0.01,
            "이미 순수구름 상태면 5/7 공식이 적용되어야 한다")
    }

    func testFlatGroundHasNoLateralDeflectionDuringSlip() {
        let ball = GolfBall(initialPosition: .zero, initialVelocity: simd_float3(0, 0, 1.0))
        ball.rollingResistance = 0.35
        let flatNormal = simd_float3(0, 1, 0)

        ball.updateForwardWithSlip(deltaTime: 0.05, surfaceNormal: flatNormal)

        XCTAssertEqual(ball.velocity.x, 0, accuracy: 0.0001,
            "평지에서는 미끄럼 구간에도 경사에 의한 옆방향 힘이 없어야 한다")
        XCTAssertLessThan(ball.velocity.z, 1.0,
            "진행 방향으로는 마찰에 의해 감속되어야 한다")
    }
}

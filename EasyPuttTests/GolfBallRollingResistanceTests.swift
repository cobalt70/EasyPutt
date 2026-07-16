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
}

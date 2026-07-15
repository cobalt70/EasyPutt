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
}

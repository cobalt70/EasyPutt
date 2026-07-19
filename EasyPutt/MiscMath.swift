//
//  RealPoints.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 2/28/25.
//  Updated by Gi Woo Kim on 7/19/26.
//
import ARKit
import SwiftUI
import Foundation
import simd

public class point3DSIMD: ObservableObject {
    @Published var position: SIMD3<Float>?  = SIMD3<Float>(0.0, 0.0, 0.0)
    init(position: SIMD3<Float>) {
        self.position = position
    }
}


struct Point3D {
    var x: Float
    var y: Float
    var z: Float
}

func dottedLine3D(from start: Point3D, to end: Point3D, numPoints: Int) -> [Point3D] {
    guard numPoints > 1 else { return [start, end] } // 최소 두 개의 점이 필요
    
    // 내부 함수: 두 점을 보간하여 중간 점을 계산
    func interpolate(t: Float) -> Point3D {
        return Point3D(
            x: start.x + t * (end.x - start.x),
            y: start.y + t * (end.y - start.y),
            z: start.z + t * (end.z - start.z)
        )
    }

    return (0..<numPoints).map { i in
        let t = Float(i) / Float(numPoints - 1) // 보간 비율 (0 ~ 1 사이)
        return interpolate(t: t)
    }
}

// 예제
//let p1 = Point3D(x: 0, y: 0, z: 0)
//let p2 = Point3D(x: 10, y: 10, z: 10)
//let points = dottedLine3D(from: p1, to: p2, numPoints: 5)

// 출력
//for point in points {
//    print("(\(point.x), \(point.y), \(point.z))")
//   }
func worldToScreen(_ point: simd_float3, with frame: ARFrame) -> CGPoint? {
    let camera = frame.camera
    let projectedPoint = camera.projectPoint(point, orientation: .portrait, viewportSize: UIScreen.main.bounds.size)
    return CGPoint(x: projectedPoint.x, y: projectedPoint.y)
}
/*

func getWorldPositionFromDepth(at point: CGPoint, in frame: ARFrame) -> simd_float3? {
    guard let sceneDepth = frame.sceneDepth else {
        return nil
    }

    // 1. Get the depth value for the specific pixel.
    let depthImage = sceneDepth.depthMap
    let width = CVPixelBufferGetWidth(depthImage)
    let height = CVPixelBufferGetHeight(depthImage)
    
    // Convert 2D screen position to depth map coordinates
    let depthX = Int(point.x * CGFloat(width) / UIScreen.main.bounds.width)
    let depthY = Int(point.y * CGFloat(height) / UIScreen.main.bounds.height)

    // Lock the base address of the depth buffer
    CVPixelBufferLockBaseAddress(depthImage, .readOnly)
    let baseAddress = CVPixelBufferGetBaseAddress(depthImage)
    let floatBuffer = baseAddress?.assumingMemoryBound(to: Float32.self)
    
    guard let buffer = floatBuffer else {
        CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)
        return nil
    }

    // Get the depth value for the specific pixel
    let depthIndex = depthY * width + depthX
    let depth = buffer[depthIndex]  // Depth value in meters

    CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)

    // 2. Use the camera's unproject method to convert the 2D point to a 3D world position.
    let camera = frame.camera
    let screenPosition = CGPoint(x: point.x, y: point.y)  // 2D screen coordinates
    let viewportSize = UIScreen.main.bounds.size  // Screen size
    
    // Get the device's interface orientation (use windowScene's interfaceOrientation)
    guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
        return nil
    }
    
    let orientation = windowScene.interfaceOrientation

    // 3. Unproject the 2D point to 3D using the depth value for z
    let worldPosition = camera.unprojectPoint(
        screenPosition,
        ontoPlane: simd_float4x4(1),  // Assuming an identity matrix for simplicity
        orientation: orientation,
        viewportSize: viewportSize,
        z: Float(depth)  // LiDAR depth value
    )
    
    return worldPosition
}
func getNormalVector(at point: CGPoint, from frame: ARFrame) -> simd_float3? {
    guard let sceneDepth = frame.sceneDepth else { return nil }
    
    // 깊이 이미지 가져오기
    let depthMap = sceneDepth.depthMap
    
    // 픽셀의 3D 위치 얻기
    let worldPosition = sceneDepth.worldPosition(for: point)
    
    // 주변 점 샘플링 (예: 좌/우/위/아래 픽셀)
    let left = sceneDepth.worldPosition(for: CGPoint(x: point.x - 1, y: point.y))
    let right = sceneDepth.worldPosition(for: CGPoint(x: point.x + 1, y: point.y))
    let top = sceneDepth.worldPosition(for: CGPoint(x: point.x, y: point.y - 1))
    let bottom = sceneDepth.worldPosition(for: CGPoint(x: point.x, y: point.y + 1))

    // 두 개의 벡터 생성
    let vector1 = right - left
    let vector2 = top - bottom
    
    // 크로스 프로덕트로 법선 벡터 계산
    let normal = simd_normalize(simd_cross(vector1, vector2))
    return normal
}
t

 func getDepthValue(at point: CGPoint, from frame: ARFrame) -> Float? {
     guard let sceneDepth = frame.sceneDepth else {
         return nil // No depth data available
     }

     // Get the depth map (CVPixelBuffer)
     let depthImage = sceneDepth.depthMap
     
     // Get the width and height of the depth image
     let width = CVPixelBufferGetWidth(depthImage)
     let height = CVPixelBufferGetHeight(depthImage)
     
     // Convert screen point to pixel coordinates in the depth map
     let depthX = Int(point.x * CGFloat(width) / UIScreen.main.bounds.width)
     let depthY = Int(point.y * CGFloat(height) / UIScreen.main.bounds.height)
     
     // Lock the pixel buffer to read its contents
     CVPixelBufferLockBaseAddress(depthImage, .readOnly)
     
     // Get the base address of the pixel buffer
     let baseAddress = CVPixelBufferGetBaseAddress(depthImage)
     
     // Create a pointer to the raw depth data (depth values are in Float32 format)
     let floatBuffer = baseAddress?.assumingMemoryBound(to: Float32.self)
     
     // Ensure the buffer is valid
     guard let buffer = floatBuffer else {
         CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)
         return nil // Invalid buffer
     }

     // Calculate the index for the depth pixel based on x, y
     let depthIndex = depthY * width + depthX
     
     // Get the depth value for the pixel (in meters)
     let depthValue = buffer[depthIndex]

     // Unlock the pixel buffer after reading the data
     CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)
     
     // Return the depth value
     return depthValue
 }

func getWorldPosition(from point: CGPoint, in frame: ARFrame) -> simd_float3? {
    guard let sceneDepth = frame.sceneDepth else { return nil }

    // depthMap의 크기 가져오기
    let depthImage = sceneDepth.depthMap
    let width = CVPixelBufferGetWidth(depthImage)
    let height = CVPixelBufferGetHeight(depthImage)
    
    // 화면 좌표를 depthMap 해상도에 맞게 변환
    let depthX = Int(point.x * CGFloat(width) / UIScreen.main.bounds.width)
    let depthY = Int(point.y * CGFloat(height) / UIScreen.main.bounds.height)

    // CVPixelBuffer에서 깊이값 가져오기
    CVPixelBufferLockBaseAddress(depthImage, .readOnly)
    let baseAddress = CVPixelBufferGetBaseAddress(depthImage)
    let floatBuffer = baseAddress?.assumingMemoryBound(to: Float32.self)
    
    guard let buffer = floatBuffer else {
        CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)
        return nil
    }

    let depthIndex = depthY * width + depthX
    let depth = buffer[depthIndex] // 해당 픽셀의 깊이값

    CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)

    // 2D 스크린 좌표를 3D 월드 좌표로 변환
    let camera = frame.camera
    
    // `CGPoint`로 스크린 좌표를 넣고, 깊이 값을 `simd_float3`의 z 값으로 사용
    let screenPosition = CGPoint(x: point.x, y: point.y) // 2D 화면 좌표
    
    // 화면의 크기
    let viewportSize = UIScreen.main.bounds.size
    
    // 화면 회전 정보
    let orientation = UIApplication.shared.statusBarOrientation

    // `ontoPlane`은 변환할 평면의 법선 벡터 (보통은 z축 기준)
    //let ontoPlane = simd_float3(0, 0, -1)
    // 평면 법선 벡터를 기준으로 4x4 행렬 생성 (예: Z축 기준 평면)
    // Z축 방향으로 평면을 정의하는 4x4 행렬을 생성
    let planeNormal = simd_float3(0, 0, -1)  // 평면의 법선 벡터
    let planePosition = simd_float3(0, 0, 0) // 평면의 위치 (원점)
    
    // 평면을 정의하는 변환 행렬 만들기
    let ontoPlane = simd_float4x4(
        columns: (
            simd_float4(planeNormal.x, 0, 0, 0),
            simd_float4(planeNormal.y, 0, 0, 0),
            simd_float4(planeNormal.z, 0, 0, 0),
            simd_float4(planePosition.x, planePosition.y, planePosition.z, 1)
        )
    )
    
    // `unprojectPoint()`를 호출하여 3D 월드 좌표 계산
    let worldPosition = camera.unprojectPoint(
        screenPosition,
        ontoPlane: ontoPlane,
        orientation: orientation,
        viewportSize: viewportSize
    //    z: Float(depth)
    )
    
    return worldPosition
}


func getWorldPositionWithLiDAR(from point: CGPoint, in frame: ARFrame) -> simd_float3? {
    guard let sceneDepth = frame.sceneDepth else { return nil }

    // LiDAR 깊이 맵 가져오기
    let depthImage = sceneDepth.depthMap
    let width = CVPixelBufferGetWidth(depthImage)
    let height = CVPixelBufferGetHeight(depthImage)
    
    // 화면 좌표를 depthMap 해상도에 맞게 변환
    let depthX = Int(point.x * CGFloat(width) / UIScreen.main.bounds.width)
    let depthY = Int(point.y * CGFloat(height) / UIScreen.main.bounds.height)

    // CVPixelBuffer에서 깊이값 가져오기
    CVPixelBufferLockBaseAddress(depthImage, .readOnly)
    let baseAddress = CVPixelBufferGetBaseAddress(depthImage)
    let floatBuffer = baseAddress?.assumingMemoryBound(to: Float32.self)
    
    guard let buffer = floatBuffer else {
        CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)
        return nil
    }

    let depthIndex = depthY * width + depthX
    let depth = buffer[depthIndex] // 해당 픽셀의 깊이값

    CVPixelBufferUnlockBaseAddress(depthImage, .readOnly)

    // 카메라의 변환 행렬을 가져오기
    let camera = frame.camera
    let cameraTransform = camera.transform // This is a simd_float4x4 matrix

    // 화면 좌표를 3D 월드 좌표로 변환
    let screenPosition = CGPoint(x: point.x, y: point.y) // 2D 화면 좌표
    
    // 화면의 크기
    let viewportSize = UIScreen.main.bounds.size
    
    // 화면 회전 정보
    let orientation = UIApplication.shared.statusBarOrientation
     //Get the device's interface orientation (use windowScene's interfaceOrientation)
    
//    if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
//        let orientation = windowScene.interfaceOrientation
//    } else {
//        // Handle the case where there is no window scene
//    }

       
    
    // 평면 법선 벡터를 기준으로 4x4 행렬 생성 (예: Z축 기준 평면)
    // Z축 방향으로 평면을 정의하는 4x4 행렬을 생성
    let planeNormal = simd_float3(0, 0, -1)  // 평면의 법선 벡터
    let planePosition = simd_float3(0, 0, 0) // 평면의 위치 (원점)
    
    // 평면을 정의하는 변환 행렬 만들기
    let ontoPlane = simd_float4x4(
        columns: (
            simd_float4(planeNormal.x, 0, 0, 0),
            simd_float4(planeNormal.y, 0, 0, 0),
            simd_float4(planeNormal.z, 0, 0, 0),
            simd_float4(planePosition.x, planePosition.y, planePosition.z, 1)
        )
    )
    
    // LiDAR를 사용하여 unprojectPoint를 호출하여 3D 월드 좌표 계산
    let worldPosition = camera.unprojectPoint(
        screenPosition,
        ontoPlane: ontoPlane,
        orientation: orientation,
        viewportSize: viewportSize
       
    )
    
    return worldPosition
}
*/

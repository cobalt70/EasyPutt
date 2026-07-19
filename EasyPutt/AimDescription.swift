//
//  AimDescription.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 7/19/26.
//  Updated by Gi Woo Kim on 7/19/26.
//

import Foundation

/// 좌우 조준 오프셋(cm, 부호 있음: 양수=오른쪽/음수=왼쪽)을 홀 반경/공 크기 기준
/// 컵 단위 문구로 변환한다. `ArViewModel.aimOffsetCentimeters`의 반환값을 그대로 받는다.
func describeAimOffset(centimeters: Float) -> String {
    let cupRadius: Float = 0.054
    let ballSize: Float = 0.0427
    let cutoff1: Float = 0.02
    let cutoff2: Float = cupRadius
    let cutoff3: Float = cupRadius + ballSize
    let cupSize: Float = 0.108

    let aimInMeters = abs(centimeters) / 100
    let direction = centimeters < 0 ? "왼쪽" : "오른쪽"

    switch aimInMeters {
    case 0..<cutoff1:
        return "홀컵 중앙"
    case cutoff1..<cutoff2:
        return "\(direction) 홀컵 안쪽"
    case cutoff2..<cutoff3:
        return "\(direction) 홀컵 밖 (공 1개)"
    default:
        let cups = (aimInMeters - cupRadius) / cupSize
        let roundedCups = round(cups * 2) / 2
        return String(format: "%@ %.1f컵 아웃", direction, roundedCups)
    }
}

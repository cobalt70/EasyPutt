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
        // cups가 정확히 0.5 단위 경계(예: 0.75)에 걸리면 그 앞 계산의 부동소수점 오차로
        // 반올림이 아래(0.5)/위(1.0)로 흔들릴 수 있다 — 0.5컵 단위로 스냅하기 전에
        // 먼저 밀리컵 단위로 반올림해 오차를 죽인다.
        let cupsStable = (cups * 1000).rounded() / 1000
        let roundedCups = (cupsStable * 2).rounded() / 2
        return String(format: "%@ %.1f컵 아웃", direction, roundedCups)
    }
}

//
//  CollisionGroup.swift
//  EasyPutt
//
//  Created by Gi Woo Kim on 3/21/25.
//  Updated by Gi Woo Kim on 7/19/26.
//

import RealityKit

enum CollisionGroups {
    static let projectedTile = CollisionGroup(rawValue: 1 << 0) // 타일
    static let golfBall = CollisionGroup(rawValue: 1 << 1) // 골프공
    static let scull = CollisionGroup(rawValue: 1 << 2) // 화살표(Scull)
    static let displayGround = CollisionGroup(rawValue: 1 << 3) // 바닥
}

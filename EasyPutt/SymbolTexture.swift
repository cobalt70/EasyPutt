//
//  SymbolTexture.swift
//  EasyPutt
//

import UIKit
import RealityKit

/// SF Symbol을 배경이 투명한 텍스처로 렌더링해서 RealityKit 머티리얼 파라미터로 반환한다.
/// FocusEntity(지면 트래킹 리티클)를 불투명 사각형 대신 "+" 모양만 보이게 하는 데 쓴다.
func textureFromSymbol(named symbolName: String, color: UIColor, backgroundColor: UIColor, backgroundAlpha: CGFloat) throws -> MaterialColorParameter {
    let config = UIImage.SymbolConfiguration(pointSize: 100, weight: .regular)

    guard let symbolImage = UIImage(systemName: symbolName, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else {
        throw NSError(domain: "SymbolTextureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load symbol \(symbolName)"])
    }

    let size = symbolImage.size
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    defer { UIGraphicsEndImageContext() }
    guard let context = UIGraphicsGetCurrentContext() else {
        throw NSError(domain: "SymbolTextureError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get graphics context"])
    }

    context.setFillColor(backgroundColor.withAlphaComponent(backgroundAlpha).cgColor)
    context.fill(CGRect(origin: .zero, size: size))

    let tintedSymbol = symbolImage.withTintColor(color, renderingMode: .automatic)
    tintedSymbol.draw(in: CGRect(origin: .zero, size: size))

    guard let finalImage = UIGraphicsGetImageFromCurrentImageContext(),
          let cgImage = finalImage.cgImage else {
        throw NSError(domain: "SymbolTextureError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get final image or cgImage"])
    }

    let texture: TextureResource
    if #available(iOS 18.0, *) {
        texture = try TextureResource(image: cgImage, options: .init(semantic: .color))
    } else {
        texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
    }

    return .texture(texture)
}

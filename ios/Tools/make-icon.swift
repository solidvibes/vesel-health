import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let s = CGFloat(size)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func blob(_ ctx: CGContext, x: CGFloat, y: CGFloat, r: CGFloat, color: UInt32, alpha: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(color, alpha), rgb(color, 0)] as CFArray, locations: [0, 1])!
    let center = CGPoint(x: x * s, y: (1 - y) * s)
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: r * s, options: [])
}

func render(_ name: String, background: UInt32, blobs: Bool, blobAlpha: CGFloat, ring: UInt32) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(background))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    if blobs {
        blob(ctx, x: 0.25, y: 0.20, r: 0.75, color: 0x2F9E5B, alpha: 0.75 * blobAlpha)
        blob(ctx, x: 0.85, y: 0.45, r: 0.70, color: 0x3B6CF6, alpha: 0.70 * blobAlpha)
        blob(ctx, x: 0.35, y: 0.95, r: 0.70, color: 0xD9621B, alpha: 0.60 * blobAlpha)
    }
    let lineWidth = s * 20 / 180
    let radius = s * 44 / 180
    ctx.setStrokeColor(rgb(ring))
    ctx.setLineWidth(lineWidth)
    ctx.addArc(center: CGPoint(x: s / 2, y: s / 2), radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

render("AppIcon.png", background: 0xF3F3F1, blobs: true, blobAlpha: 1, ring: 0xFFFFFF)
render("AppIcon-Dark.png", background: 0x0E0F11, blobs: true, blobAlpha: 0.8, ring: 0xF2F2F4)
render("AppIcon-Tinted.png", background: 0x000000, blobs: false, blobAlpha: 0, ring: 0xFFFFFF)

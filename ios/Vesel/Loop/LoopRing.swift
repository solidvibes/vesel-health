import SwiftUI
import UIKit

/// The app icon's single ring, drawn as a template image for the tab bar's Loop button. While a read runs a quarter of it
/// is drawn bold and turns: one animated image, so the tab bar turns it on its own; with Reduce Motion the whole ring is just dimmed.
/// With the Loop's battery low it is drawn in the stress colour instead.
enum LoopRing {
    static let frames = 60
    static let turn: TimeInterval = 1.2

    /// Idle, still and turning, drawn once each in ink (template, tinted by the tab bar) and once in the stress colour.
    private struct Images {
        let idle: UIImage
        let still: UIImage
        let turning: UIImage

        @MainActor init(_ paint: (UIImage) -> UIImage) {
            idle = paint(frame(reading: false, reduceMotion: false, angle: 0))
            still = paint(frame(reading: true, reduceMotion: true, angle: 0))
            let images = (0..<frames).map { paint(frame(reading: true, reduceMotion: false, angle: CGFloat($0) / CGFloat(frames) * 2 * .pi)) }
            turning = UIImage.animatedImage(with: images, duration: turn) ?? idle
        }
    }

    @MainActor private static let ink = Images { $0 }
    @MainActor private static let low = Images { $0.withTintColor(UIColor(named: "Stress")!, renderingMode: .alwaysOriginal) }

    @MainActor static func image(reading: Bool, reduceMotion: Bool, low isLow: Bool) -> UIImage {
        let images = isLow ? low : ink
        guard reading else { return images.idle }
        return reduceMotion ? images.still : images.turning
    }

    @MainActor private static func frame(reading: Bool, reduceMotion: Bool, angle: CGFloat) -> UIImage {
        let side: CGFloat = 30
        let outer: CGFloat = 24
        let lineWidth = outer * 20 / 108
        let radius = (outer - lineWidth) / 2
        let center = CGPoint(x: side / 2, y: side / 2)
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let context = renderer.cgContext
            context.setLineWidth(lineWidth)
            context.setLineCap(.round)
            context.setStrokeColor(UIColor.black.cgColor)
            context.setAlpha(reading ? (reduceMotion ? 0.4 : 0.3) : 1)
            context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            context.strokePath()
            guard reading, !reduceMotion else { return }
            context.setAlpha(1)
            let start = -CGFloat.pi / 2 + angle
            context.addArc(center: center, radius: radius, startAngle: start, endAngle: start + .pi / 2, clockwise: false)
            context.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}

import UIKit

/// One-shot CAEmitterLayer burst. Particles are simulated & rendered by the render server,
/// so hundreds of them cost the main thread nothing.
enum Confetti {
    private static let images: [CGImage] = {
        let colors: [UIColor] = [Theme.yes, Theme.accent, .systemYellow, .systemPink, .white]
        return colors.compactMap { color in
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 12)).image { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
            }.cgImage
        }
    }()

    static func burst(in view: UIView, at point: CGPoint) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.beginTime = CACurrentMediaTime() // otherwise the emitter "pre-warms" from time 0
        emitter.emitterCells = images.map { image in
            let cell = CAEmitterCell()
            cell.contents = image
            cell.birthRate = 70
            cell.lifetime = 3
            cell.velocity = 420
            cell.velocityRange = 160
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 3
            cell.yAcceleration = 600
            cell.spin = 4
            cell.spinRange = 10
            cell.scale = 0.7
            cell.scaleRange = 0.35
            cell.alphaSpeed = -0.35
            return cell
        }
        view.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { emitter.removeFromSuperlayer() }
    }
}

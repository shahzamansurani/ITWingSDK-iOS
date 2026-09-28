import UIKit

/// Shared card surface for real and custom native ads.
final class ITWingNativeAdCard: UIView {
    private let gradient = CAGradientLayer()
    private let shadowLayer = CALayer()
    private var surfaceElevation: CGFloat = 0
    var innerPadding: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.colors = [
            UIColor(red: 17 / 255, green: 24 / 255, blue: 39 / 255, alpha: 0.87).cgColor,
            UIColor(red: 31 / 255, green: 41 / 255, blue: 55 / 255, alpha: 0.69).cgColor,
            UIColor(red: 2 / 255, green: 6 / 255, blue: 23 / 255, alpha: 0.82).cgColor,
        ]
        gradient.locations = [0, 0.5, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradient, at: 0)
    }

    required init?(coder: NSCoder) { nil }

    func useSolidColor(_ color: UIColor) {
        gradient.colors = [color.cgColor, color.cgColor]
        gradient.locations = [0, 1]
    }

    func setSurfaceElevation(_ elevation: CGFloat) {
        surfaceElevation = elevation
        updateShadowLayer()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateShadowLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
        updateShadowLayer()
    }

    private func updateShadowLayer() {
        guard surfaceElevation > 0, let superview else {
            shadowLayer.removeFromSuperlayer()
            return
        }
        if shadowLayer.superlayer !== superview.layer {
            shadowLayer.removeFromSuperlayer()
            superview.layer.insertSublayer(shadowLayer, below: layer)
        }
        shadowLayer.frame = convert(bounds, to: superview)
        shadowLayer.shadowPath = UIBezierPath(roundedRect: shadowLayer.bounds, cornerRadius: layer.cornerRadius).cgPath
        ITWingAdTheme.configureShadow(shadowLayer, elevation: surfaceElevation)
    }
}

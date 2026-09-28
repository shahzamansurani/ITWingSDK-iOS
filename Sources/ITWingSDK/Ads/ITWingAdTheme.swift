import UIKit

/// Normalizes the existing admin `app.colors` contract for ad renderers.
enum ITWingAdTheme {
    static let defaultAccent = UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1)
    struct AdCardStyle {
        let backgroundColor: UIColor
        let cornerRadius: CGFloat
        let elevation: CGFloat
        let borderColor: UIColor?
        let borderWidth: CGFloat
        let innerPadding: CGFloat
    }

    static func shimmerBase(appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }) -> UIColor {
        color(appKeys: ["media_shimmer_base_color"], fallback: UIColor(white: 64.0 / 255.0, alpha: 1), appColorProvider: appColorProvider)
    }

    static func shimmerHighlight(appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }) -> UIColor {
        color(appKeys: ["media_shimmer_highlight_color", "primary", "primary_color", "accent"], fallback: .white, appColorProvider: appColorProvider)
    }

    static func primary(fallback: UIColor = defaultAccent) -> UIColor {
        color(appKeys: ["primary", "primary_color", "accent"], fallback: fallback)
    }

    static func cardBackground(
        format: String,
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        let native = format.lowercased() == "native"
        let specific = native ? "native_card_background_color" : "banner_card_background_color"
        let candidates = [specific, "ad_card_background_color"]
        for key in candidates {
            if let value = metadata[key] ?? nil, let parsed = parsed(value) { return parsed }
            let appValue = appColorProvider(key)
            if let parsed = parsed(appValue) { return parsed }
        }
        // If no card-specific color is set, honor the admin's ad background
        // fallback on the outer card as well as the legacy inner content.
        let fallbackKeys = native
            ? ["native_background_color", "banner_background_color", "ad_background_color", "surface_color", "background_color"]
            : ["banner_background_color", "ad_background_color", "surface_color", "background_color"]
        for key in fallbackKeys {
            if let value = metadata[key] ?? nil, let parsed = parsed(value) { return parsed }
            if let parsed = parsed(appColorProvider(key)) { return parsed }
        }
        return .clear
    }

    static func cardCornerRadius(format: String, metadata: [String: String?] = [:]) -> CGFloat {
        let native = format.lowercased() == "native"
        let keys = native
            ? ["native_card_corner_radius", "ad_card_corner_radius"]
            : ["banner_card_corner_radius", "ad_card_corner_radius"]
        for key in keys {
            if let metadataValue = metadata[key] ?? nil {
                let preset = normalizedCardRadius(metadataValue, fallback: -1)
                if preset >= 0 { return preset }
            }
            let appValue = ITWingSDK.getColor(key)
            let preset = normalizedCardRadius(appValue, fallback: -1)
            if preset >= 0 { return preset }
        }
        return 0
    }

    static func normalizedCardRadius(_ value: String?, fallback: CGFloat = 0) -> CGFloat {
        guard let value else { return fallback }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "none": return 0
        case "small": return 8
        case "medium": return 12
        case "large": return 16
        case "extra_large", "extra large", "xlarge": return 24
        default:
            guard let number = Double(value), number.isFinite, number >= 0, number <= 32 else { return fallback }
            return CGFloat(number)
        }
    }

    static func applyCard(_ card: ITWingNativeAdCard, format: String, metadata: [String: String?] = [:]) {
        let style = cardStyle(format: format, metadata: metadata)
        card.layer.cornerRadius = style.cornerRadius
        card.clipsToBounds = true
        card.useSolidColor(style.backgroundColor)
        card.layer.borderWidth = style.borderWidth
        card.layer.borderColor = style.borderColor?.cgColor
        card.innerPadding = style.innerPadding
        card.setSurfaceElevation(style.elevation)
    }

    static func applyBannerHost(_ host: UIView, metadata: [String: String?] = [:]) {
        let style = cardStyle(format: "banner", metadata: metadata)
        host.backgroundColor = style.backgroundColor
        host.layer.cornerRadius = style.cornerRadius
        host.layer.masksToBounds = false
        host.layer.borderWidth = style.borderWidth
        host.layer.borderColor = style.borderColor?.cgColor
        host.layoutMargins = UIEdgeInsets(top: style.innerPadding, left: style.innerPadding, bottom: style.innerPadding, right: style.innerPadding)
        configureShadow(host.layer, elevation: style.elevation)
    }

    static func cardStyle(
        format: String,
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> AdCardStyle {
        let native = format.lowercased() == "native"
        let prefix = native ? "native" : "banner"
        let generic = { (suffix: String) in "ad_card_\(suffix)" }
        let elevation = surfacePreset(keys: ["\(prefix)_card_elevation", generic("elevation")], metadata: metadata, provider: appColorProvider, presets: ["none": 0, "subtle": 2, "medium": 6, "strong": 10], maximum: 16)
        let borderWidth = surfacePreset(keys: ["\(prefix)_card_border_width", generic("border_width")], metadata: metadata, provider: appColorProvider, presets: ["none": 0, "thin": 1, "medium": 2], maximum: 4)
        let padding = surfacePreset(keys: ["\(prefix)_card_padding", generic("padding")], metadata: metadata, provider: appColorProvider, presets: ["none": 0, "compact": 8, "comfortable": 12], maximum: 24)
        let cardBorderColor = configuredColor(metadata: metadata,
            metadataKeys: ["\(prefix)_card_border_color", generic("border_color")],
            appKeys: ["\(prefix)_card_border_color", generic("border_color")], appColorProvider: appColorProvider)
        let legacyStroke = configuredColor(metadata: metadata,
            metadataKeys: ["\(prefix)_stroke_color", "stroke_color"],
            appKeys: ["\(prefix)_stroke_color", "ad_stroke_color", "stroke_color"], appColorProvider: appColorProvider)
        let effectiveBorderWidth = borderWidth > 0 ? borderWidth : (legacyStroke == nil ? 0 : 1)
        return AdCardStyle(backgroundColor: cardBackground(format: format, metadata: metadata, appColorProvider: appColorProvider),
            cornerRadius: cardCornerRadius(format: format, metadata: metadata), elevation: elevation,
            borderColor: cardBorderColor ?? legacyStroke, borderWidth: effectiveBorderWidth, innerPadding: padding)
    }

    static func normalizedCardElevation(_ value: String?) -> CGFloat {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "subtle": return 2
        case "medium": return 6
        case "strong": return 10
        case "none", "0", "0dp", nil: return 0
        default: return normalizedNumeric(value, range: 0...16)
        }
    }

    static func configureShadow(_ layer: CALayer, elevation: CGFloat) {
        guard elevation > 0 else {
            layer.shadowOpacity = 0
            layer.shadowRadius = 0
            layer.shadowOffset = .zero
            layer.shadowPath = nil
            return
        }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = elevation >= 10 ? 0.2 : (elevation >= 6 ? 0.16 : 0.12)
        layer.shadowRadius = elevation >= 10 ? 7 : (elevation >= 6 ? 5 : 3)
        layer.shadowOffset = CGSize(width: 0, height: elevation >= 10 ? 4 : (elevation >= 6 ? 3 : 1))
    }

    private static func surfacePreset(keys: [String], metadata: [String: String?], provider: (String) -> String, presets: [String: CGFloat], maximum: CGFloat) -> CGFloat {
        for key in keys {
            let value = (metadata[key] ?? nil) ?? provider(key)
            guard !value.isEmpty else { continue }
            if let preset = presets[value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] { return preset }
            let rawNumber = value.replacingOccurrences(of: "dp", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let number = Double(rawNumber), number.isFinite, number >= 0, number <= Double(maximum) { return CGFloat(number) }
        }
        return 0
    }

    private static func normalizedNumeric(_ value: String?, range: ClosedRange<CGFloat>) -> CGFloat {
        guard let value, let number = Double(value.replacingOccurrences(of: "dp", with: "").trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite, number >= Double(range.lowerBound), number <= Double(range.upperBound) else { return 0 }
        return CGFloat(number)
    }

    static func color(
        metadata: [String: String?] = [:],
        metadataKeys: [String] = [],
        appKeys: [String],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        for key in metadataKeys {
            if let value = metadata[key] ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let parsed = parsed(value) {
                return parsed
            }
        }
        for key in appKeys {
            let value = appColorProvider(key)
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                let parsed = parsed(value) {
                return parsed
            }
        }
        return fallback
    }

    static func nativeCTA(
        metadata: [String: String?] = [:],
        fallback: UIColor = defaultAccent,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_cta_color", "native_cta_background_color", "cta_background_color"],
            appKeys: ["native_cta_color", "native_cta_background_color", "ad_cta_color", "ad_cta_background_color", "primary", "primary_color", "accent"],
            fallback: fallback,
            appColorProvider: appColorProvider
        )
    }

    static func nativeCTAText(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_cta_text_color", "ad_cta_text_color", "cta_text_color"],
            appKeys: ["native_cta_text_color", "ad_cta_text_color", "cta_text_color"],
            fallback: .white,
            appColorProvider: appColorProvider
        )
    }

    static func nativeLabel(
        metadata: [String: String?] = [:],
        fallback: UIColor = defaultAccent,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_ad_label_background_color", "native_ad_label_color", "ad_label_background_color", "ad_badge_background_color"],
            appKeys: ["native_ad_label_background_color", "native_ad_label_color", "ad_label_background_color", "ad_badge_background_color", "primary", "primary_color", "accent"],
            fallback: fallback,
            appColorProvider: appColorProvider
        )
    }

    static func nativeLabelText(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_ad_label_text_color", "ad_label_text_color", "ad_badge_text_color"],
            appKeys: ["native_ad_label_text_color", "ad_label_text_color", "ad_badge_text_color"],
            fallback: .white,
            appColorProvider: appColorProvider
        )
    }

    static func nativeBackground(
        metadata: [String: String?] = [:],
        fallback: UIColor = .clear,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_background_color", "banner_background_color", "ad_background_color", "background_color"],
            appKeys: ["native_background_color", "banner_background_color", "ad_background_color", "surface_color", "background_color"],
            fallback: fallback,
            appColorProvider: appColorProvider
        )
    }

    static func bannerBackground(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor? {
        configuredColor(metadata: metadata, metadataKeys: ["banner_background_color", "background_color"], appKeys: ["banner_background_color", "ad_background_color", "surface_color", "background_color"], appColorProvider: appColorProvider)
    }

    static func nativeBorder(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_stroke_color", "stroke_color"],
            appKeys: ["native_stroke_color", "ad_stroke_color", "stroke_color"],
            fallback: UIColor.white.withAlphaComponent(0.33),
            appColorProvider: appColorProvider
        )
    }

    static func bannerBorder(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor? {
        configuredColor(metadata: metadata, metadataKeys: ["banner_stroke_color", "stroke_color"], appKeys: ["banner_stroke_color", "ad_stroke_color", "stroke_color"], appColorProvider: appColorProvider)
    }

    static func bannerText(
        metadata: [String: String?] = [:],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["banner_text_color", "text_color"], appKeys: ["banner_text_color", "native_text_color", "text_color"], fallback: fallback, appColorProvider: appColorProvider)
    }

    static func bannerSecondary(
        metadata: [String: String?] = [:],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["banner_text_color", "native_secondary_text_color", "native_meta_text_color", "secondary_text_color", "text_color"], appKeys: ["banner_text_color", "native_secondary_text_color", "native_meta_text_color", "secondary_text_color", "text_color"], fallback: fallback, appColorProvider: appColorProvider)
    }

    static func bannerCTA(
        metadata: [String: String?] = [:],
        fallback: UIColor = defaultAccent,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["banner_cta_color", "banner_cta_background_color", "cta_background_color"], appKeys: ["banner_cta_color", "banner_cta_background_color", "ad_cta_color", "ad_cta_background_color", "primary", "primary_color", "accent"], fallback: fallback, appColorProvider: appColorProvider)
    }

    static func bannerCTAText(
        metadata: [String: String?] = [:],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["banner_cta_text_color", "native_cta_text_color", "cta_text_color"], appKeys: ["banner_cta_text_color", "native_cta_text_color", "cta_text_color"], fallback: .white, appColorProvider: appColorProvider)
    }

    static func nativeHeadline(
        metadata: [String: String?] = [:],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["native_headline_text_color", "native_text_color", "headline_text_color", "banner_text_color", "text_color"], appKeys: ["native_text_color", "native_headline_text_color", "headline_text_color", "banner_text_color", "text_color"], fallback: fallback, appColorProvider: appColorProvider)
    }

    static func nativeBody(
        metadata: [String: String?] = [:],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(metadata: metadata, metadataKeys: ["native_body_text_color", "native_secondary_text_color", "body_text_color", "secondary_text_color"], appKeys: ["native_body_text_color", "native_secondary_text_color", "body_text_color", "secondary_text_color", "native_text_color"], fallback: fallback, appColorProvider: appColorProvider)
    }

    static func nativeMeta(
        metadata: [String: String?] = [:],
        fallback: UIColor,
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor {
        color(
            metadata: metadata,
            metadataKeys: ["native_meta_text_color", "native_secondary_text_color", "meta_text_color", "secondary_text_color"],
            appKeys: ["native_meta_text_color", "native_secondary_text_color", "meta_text_color", "secondary_text_color", "native_text_color"],
            fallback: fallback,
            appColorProvider: appColorProvider
        )
    }

    static func parsed(_ value: String) -> UIColor? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard raw.count == 3 || raw.count == 4 || raw.count == 6 || raw.count == 8,
              raw.allSatisfy({ $0.isHexDigit }),
              let parsed = UInt64(raw, radix: 16) else { return nil }

        let argb: UInt64
        switch raw.count {
        case 3:
            let rgb = raw.map { "\($0)\($0)" }.joined()
            guard let expanded = UInt64(rgb, radix: 16) else { return nil }
            argb = 0xff00_0000 | expanded
        case 4: // Android-compatible #ARGB shorthand
            let expanded = raw.map { "\($0)\($0)" }.joined()
            guard let value = UInt64(expanded, radix: 16) else { return nil }
            argb = value
        case 6:
            argb = 0xff00_0000 | parsed
        default: // Android-compatible #AARRGGBB
            argb = parsed
        }

        return UIColor(
            red: CGFloat((argb >> 16) & 0xff) / 255,
            green: CGFloat((argb >> 8) & 0xff) / 255,
            blue: CGFloat(argb & 0xff) / 255,
            alpha: CGFloat((argb >> 24) & 0xff) / 255
        )
    }

    private static func configuredColor(
        metadata: [String: String?],
        metadataKeys: [String],
        appKeys: [String],
        appColorProvider: (String) -> String = { ITWingSDK.getColor($0) }
    ) -> UIColor? {
        for key in metadataKeys {
            if let value = metadata[key] ?? nil, let result = parsed(value) { return result }
        }
        for key in appKeys {
            let value = appColorProvider(key)
            if let result = parsed(value) { return result }
        }
        return nil
    }
}

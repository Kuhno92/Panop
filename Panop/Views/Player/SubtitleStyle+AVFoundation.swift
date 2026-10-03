import AVFoundation
import CoreMedia

nonisolated extension SubtitleStyle {
    /// The style as a rule for AVPlayer's own captions, or nil while the person has not changed it, so
    /// the system's caption setting stays in charge.
    var textStyleRule: AVTextStyleRule? {
        guard isCustomised else { return nil }
        let color = tint.components
        var attributes: [String: Any] = [
            kCMTextMarkupAttribute_ForegroundColorARGB as String: [1.0, color.red, color.green, color.blue],
            kCMTextMarkupAttribute_RelativeFontSize as String: size.scale * 100
        ]
        if backdrop == .none {
            attributes[kCMTextMarkupAttribute_CharacterEdgeStyle as String] =
                kCMTextMarkupCharacterEdgeStyle_DropShadow as String
        } else {
            attributes[kCMTextMarkupAttribute_BackgroundColorARGB as String] = [backdrop.opacity, 0.0, 0.0, 0.0]
        }
        return AVTextStyleRule(textMarkupAttributes: attributes)
    }
}

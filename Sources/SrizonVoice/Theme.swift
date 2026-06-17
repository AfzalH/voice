import AppKit
import SwiftUI

// MARK: - VoiceTheme

enum VoiceTheme {
    static var background: Color { Color(nsColor: .voiceBackground) }
    static var surface: Color { Color(nsColor: .voiceSurface) }
    static var raisedSurface: Color { Color(nsColor: .voiceRaisedSurface) }
    static var surfaceVariant: Color { Color(nsColor: .voiceSurfaceVariant) }
    static var previewCanvas: Color { Color(nsColor: .voicePreviewCanvas) }
    static var primary: Color { Color(nsColor: .voicePrimary) }
    static var primaryContainer: Color { Color(nsColor: .voicePrimaryContainer) }
    static var onPrimary: Color { Color(nsColor: .voiceOnPrimary) }
    static var onSurface: Color { Color(nsColor: .voiceOnSurface) }
    static var secondaryText: Color { Color(nsColor: .voiceSecondaryText) }
    static var outline: Color { Color(nsColor: .voiceOutline) }
    static var outlineVariant: Color { Color(nsColor: .voiceOutlineVariant) }
    static var error: Color { Color(nsColor: .voiceError) }
    static var warning: Color { Color(nsColor: .voiceWarning) }
    static var success: Color { Color(nsColor: .voiceSuccess) }
}

extension NSColor {
    static let voiceAzureMist = NSColor(hex: 0xECF8F8)
    static let voiceAlabasterGrey = NSColor(hex: 0xEEE4E1)
    static let voiceAlmondCream = NSColor(hex: 0xE7D8C9)
    static let voiceAlmondSilk = NSColor(hex: 0xE6BEAE)
    static let voiceCamel = NSColor(hex: 0xB2967D)
    static let voiceDeepCamel = NSColor(hex: 0x8C6E54)

    static let voiceBackground = voiceAdaptive(
        light: NSColor(hex: 0xF1E9E4),
        dark: NSColor(hex: 0x191512)
    )
    static let voiceSurface = voiceAdaptive(
        light: NSColor(hex: 0xFBF7F4),
        dark: NSColor(hex: 0x211B16)
    )
    static let voiceRaisedSurface = voiceAdaptive(
        light: NSColor(hex: 0xFFFDFC),
        dark: NSColor(hex: 0x29211B)
    )
    static let voiceSurfaceVariant = voiceAdaptive(
        light: .voiceAlmondCream,
        dark: NSColor(hex: 0x3A3027)
    )
    static let voicePreviewCanvas = voiceAdaptive(
        light: .voiceAzureMist,
        dark: NSColor(hex: 0x1F2A2A)
    )
    static let voicePrimary = voiceAdaptive(
        light: .voiceDeepCamel,
        dark: .voiceAlmondSilk
    )
    static let voicePrimaryContainer = voiceAdaptive(
        light: .voiceAlmondSilk,
        dark: NSColor(hex: 0x6B5848)
    )
    static let voiceOnPrimary = voiceAdaptive(
        light: .white,
        dark: NSColor(hex: 0x3E2A1A)
    )
    static let voiceAccentButton = voiceAdaptive(
        light: .voiceDeepCamel,
        dark: NSColor(hex: 0x8A6A4E)
    )
    static let voiceOnAccentButton = voiceAdaptive(
        light: .white,
        dark: NSColor(hex: 0xFCF3EA)
    )
    static let voiceOnSurface = voiceAdaptive(
        light: NSColor(hex: 0x2C231C),
        dark: NSColor(hex: 0xECE1D8)
    )
    static let voiceSecondaryText = voiceAdaptive(
        light: NSColor(hex: 0x6E5D4E),
        dark: NSColor(hex: 0xD4C3B2)
    )
    static let voiceOutline = voiceAdaptive(
        light: NSColor(hex: 0xB8A793),
        dark: NSColor(hex: 0x9C8A78)
    )
    static let voiceOutlineVariant = voiceAdaptive(
        light: NSColor(hex: 0xD8C8B8),
        dark: NSColor(hex: 0x4E4337)
    )
    static let voiceError = voiceAdaptive(
        light: NSColor(hex: 0x9C4434),
        dark: NSColor(hex: 0xFFB4A4)
    )
    static let voiceWarning = voiceAdaptive(
        light: NSColor(hex: 0xAF6A32),
        dark: NSColor(hex: 0xE8A188)
    )
    static let voiceSuccess = voiceAdaptive(
        light: NSColor(hex: 0x5D7E63),
        dark: NSColor(hex: 0xA9C8A9)
    )

    convenience init(hex: Int, alpha: CGFloat = 1.0) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    private static func voiceAdaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        }
    }
}

// MARK: - Button Styles

struct VoicePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .foregroundStyle(Color(nsColor: .voiceOnAccentButton).opacity(isEnabled ? 1.0 : 0.55))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .voiceAccentButton).opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1.0) : 0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.18 : 0.08), lineWidth: 1)
            )
    }
}

struct VoiceSoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .foregroundStyle(VoiceTheme.onSurface.opacity(isEnabled ? 1.0 : 0.45))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VoiceTheme.surfaceVariant.opacity(isEnabled ? (configuration.isPressed ? 0.90 : 0.72) : 0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(VoiceTheme.outlineVariant.opacity(isEnabled ? 0.72 : 0.30), lineWidth: 1)
            )
    }
}

struct VoiceQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .foregroundStyle(VoiceTheme.onSurface.opacity(isEnabled ? 1.0 : 0.45))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VoiceTheme.surfaceVariant.opacity(isEnabled ? (configuration.isPressed ? 0.64 : 0.42) : 0.22))
            )
    }
}

struct VoicePillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .frame(minHeight: 28)
            .foregroundStyle(VoiceTheme.onSurface.opacity(isEnabled ? 1.0 : 0.45))
            .background(
                Capsule(style: .continuous)
                    .fill(VoiceTheme.primaryContainer.opacity(isEnabled ? (configuration.isPressed ? 0.70 : 0.48) : 0.24))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(VoiceTheme.outlineVariant.opacity(0.64), lineWidth: 1)
            )
    }
}

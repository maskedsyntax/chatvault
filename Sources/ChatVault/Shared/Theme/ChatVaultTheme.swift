import SwiftUI

enum ChatVaultTheme {
    static func chatBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.04, green: 0.08, blue: 0.10)
            : Color(red: 0.90, green: 0.87, blue: 0.84)
    }

    static func sentBubble(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.02, green: 0.28, blue: 0.25)
            : Color(red: 0.85, green: 0.98, blue: 0.76)
    }

    static func receivedBubble(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.125, green: 0.173, blue: 0.2)
            : Color.white
    }

    static func receivedBubbleBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.06)
    }

    static func sentBubbleShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.clear
            : Color(red: 0.2, green: 0.45, blue: 0.15).opacity(0.12)
    }

    static func receivedBubbleShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.clear
            : Color.black.opacity(0.08)
    }

    static var sentCheckmark: Color {
        Color(red: 0.34, green: 0.72, blue: 0.98)
    }

    static func systemPill(for colorScheme: ColorScheme) -> Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.25 : 0.15)
    }

    static var mediaPlaceholder: Color { .secondary }

    static func dateSeparator(for colorScheme: ColorScheme) -> Color {
        Color.secondary.opacity(colorScheme == .dark ? 0.35 : 0.2)
    }

    static var highlightFlash: Color {
        Color.yellow.opacity(0.35)
    }

    static var warningBanner: Color {
        Color.yellow.opacity(0.15)
    }

    static var duplicateBanner: Color {
        Color.orange.opacity(0.15)
    }
}

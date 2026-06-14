import SwiftUI

enum ChatVaultTheme {
    static func chatBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.09)
            : Color(red: 0.93, green: 0.93, blue: 0.91)
    }

    static func sentBubble(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.0, green: 0.36, blue: 0.29)
            : Color(red: 0.86, green: 0.97, blue: 0.78)
    }

    static func receivedBubble(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.15, green: 0.15, blue: 0.15)
            : Color.white
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

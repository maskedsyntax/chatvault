import SwiftUI
#if os(macOS)
import AppKit
#endif

enum ChatVaultLogo {
    #if os(macOS)
    static func nsImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: "logo")
    }

    @MainActor
    static func configureApplicationIconIfNeeded() {
        // In a packaged .app, Info.plist AppIcon.icns already gets the macOS squircle
        // treatment. Setting applicationIconImage with a raw PNG overrides that and
        // renders as a literal square in the Dock.
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }
        guard let image = nsImage() else { return }
        NSApplication.shared.applicationIconImage = image
    }
    #endif
}

struct ChatVaultLogoView: View {
    var size: CGFloat = 72

    var body: some View {
        #if os(macOS)
        if let image = ChatVaultLogo.nsImage() {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        } else {
            fallbackSymbol
        }
        #else
        fallbackSymbol
        #endif
    }

    private var fallbackSymbol: some View {
        Image(systemName: "lock.message")
            .font(.system(size: size * 0.62))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
    }
}

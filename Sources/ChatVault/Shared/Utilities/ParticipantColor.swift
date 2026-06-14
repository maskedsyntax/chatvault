import SwiftUI

enum ParticipantColor {
    static func color(for name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}

import SwiftUI

/// WhatsApp-style bubble — one continuous shape with a tighter corner on the outer top edge.
struct ChatBubbleShape: InsettableShape {
    enum Style: Equatable {
        case sent
        case received
    }

    var style: Style
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let large = min(16, rect.height / 2, rect.width / 4)
        let small: CGFloat = 4

        let radii = switch style {
        case .sent:
            RectangleCornerRadii(
                topLeading: large,
                bottomLeading: large,
                bottomTrailing: large,
                topTrailing: small
            )
        case .received:
            RectangleCornerRadii(
                topLeading: small,
                bottomLeading: large,
                bottomTrailing: large,
                topTrailing: large
            )
        }

        return Path(roundedRect: rect, cornerRadii: radii, style: .continuous)
    }

    func inset(by amount: CGFloat) -> ChatBubbleShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

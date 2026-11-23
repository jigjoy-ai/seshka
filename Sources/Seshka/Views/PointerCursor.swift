import AppKit
import SwiftUI

/// Shows the pointing hand over what opens a link, as a browser does.
private struct PointsOnHover: ViewModifier {
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != inside else { return }
                inside = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            // Gone while the pointer was still on it: the hand must not stay.
            .onDisappear {
                if inside {
                    inside = false
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    func pointsOnHover() -> some View { modifier(PointsOnHover()) }
}

import AppKit
import Combine

/// A red dot on seshka's icon in the menu bar for as long as a downloaded update waits to be installed.
///
/// The notification that says so is on screen for a few seconds and easily missed. The dot stays.
/// It is laid over the icon, not drawn into it: the icon is a template that macOS colours to match
/// the menu bar, and an image with red in it could no longer be one.
@MainActor
enum UpdateDot {
    private static let dot = Dot(frame: NSRect(x: 0, y: 0, width: 6.5, height: 6.5))
    private static var watching: Set<AnyCancellable> = []

    /// Follows the updater, and looks again after every scan: SwiftUI may rebuild the menu bar item,
    /// and the count next to the icon moves things.
    static func follow(_ updater: Updater, _ store: Store) {
        updater.$availableVersion.receive(on: DispatchQueue.main)
            .sink { show($0 != nil) }
            .store(in: &watching)
        store.$lastScan.receive(on: DispatchQueue.main)
            .sink { _ in show(updater.availableVersion != nil) }
            .store(in: &watching)
    }

    private static func show(_ waiting: Bool) {
        // Not there yet in the first moments after launch. The next scan comes back to it.
        guard let button = Welcome.menuBarButton else { return }
        if dot.superview !== button {
            dot.removeFromSuperview()
            button.addSubview(dot)
        }
        // At the icon's upper right corner, whatever stands next to the icon.
        let icon = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? button.bounds
        let side = dot.frame.width
        let x = min(icon.maxX - side * 0.75, button.bounds.maxX - side)
        let y = button.isFlipped ? max(icon.minY - 1, 0) : min(icon.maxY - side + 1, button.bounds.maxY - side)
        dot.frame.origin = NSPoint(x: x, y: y)
        dot.isHidden = !waiting
    }

    private final class Dot: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.systemRed.cgColor
            layer?.cornerRadius = frame.width / 2
            isHidden = true
        }

        required init?(coder: NSCoder) { nil }

        /// A click on the dot is a click on the icon under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

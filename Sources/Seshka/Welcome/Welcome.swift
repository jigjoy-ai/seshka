import AppKit
import SwiftUI

/// The short tour shown the first time seshka runs, and again after an update that changed the tour.
/// A menu bar app opens no window of its own, so without it a new user double-clicks the app and
/// sees nothing happen.
@MainActor
enum Welcome {
    /// Which tour this is. Raise it when the tour has something new to show: everyone who saw an
    /// earlier one, or none, then gets it once, the first time the new version starts. That is how
    /// people who update learn what changed, and not only people who install.
    private static let edition = 1
    private static let key = "tourSeen"
    private static var window: NSWindow?
    private static var pointer: NSPanel?
    private static var closing: NSObjectProtocol?

    static var isDue: Bool { UserDefaults.standard.integer(forKey: key) < edition }

    static func show(store: Store) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: WelcomeView.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(WelcomeView.background)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView = NSHostingView(rootView: WelcomeView(finish: { open in finish(opening: open) }).environmentObject(store))
        window.center()
        self.window = window
        // Closed with the red button counts as seen, too.
        closing = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            Task { @MainActor in finish(opening: false) }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // The menu bar item takes a moment to appear after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { point() }
    }

    private static func finish(opening: Bool) {
        UserDefaults.standard.set(edition, forKey: key)
        if let closing { NotificationCenter.default.removeObserver(closing) }
        closing = nil
        pointer?.orderOut(nil)
        pointer = nil
        window?.orderOut(nil)
        window = nil
        if opening { menuBarButton?.performClick(nil) }
    }

    /// seshka's own item in the menu bar. SwiftUI keeps it to itself, so it is found among the app's windows.
    static var menuBarButton: NSStatusBarButton? {
        func button(in view: NSView) -> NSStatusBarButton? {
            (view as? NSStatusBarButton) ?? view.subviews.lazy.compactMap(button(in:)).first
        }
        return NSApp.windows.lazy.filter { $0.className.contains("StatusBar") }
            .compactMap { $0.contentView.flatMap(button(in:)) }.first
    }

    /// Puts an arrow under the real menu bar item for as long as the tour is open.
    private static func point() {
        guard window != nil, pointer == nil, let item = menuBarButton?.window?.frame,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(item) }),
              // An item macOS had no room for sits off the screen. Then there is nothing to point at.
              item.midX > screen.frame.minX + 40, item.midX < screen.frame.maxX - 40 else { return }
        let size = NSSize(width: 150, height: 74)
        let panel = NSPanel(contentRect: NSRect(x: item.midX - size.width / 2, y: item.minY - size.height - 2, width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.contentView = NSHostingView(rootView: PointerView())
        panel.orderFrontRegardless()
        pointer = panel
    }
}

/// "seshka is up here", bouncing under the menu bar item.
struct PointerView: View {
    @State private var up = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .bold))
            Text("seshka is here")
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(Color.black)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.yellow))
        .offset(y: up ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { up = true }
        }
    }
}

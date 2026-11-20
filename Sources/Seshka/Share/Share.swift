import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The window that shows the card before it is shared, and what its buttons do with the picture.
@MainActor
enum Share {
    private static var window: NSWindow?

    static func show(store: Store) {
        let window = self.window ?? {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: ShareView.size),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.backgroundColor = NSColor(Palette.page)
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.center()
            self.window = window
            return window
        }()
        // Made again every time, so the numbers are the ones of this moment.
        window.contentView = NSHostingView(rootView: ShareView(tally: store.history.week(), period: store.history.period()))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The card as a PNG, at twice the size it is drawn at so it stays sharp.
    static func png(_ tally: History.Tally, period: String) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(tally: tally, period: period))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func copy(_ png: Data) {
        let board = NSPasteboard.general
        // Both kinds: browsers take the PNG, some older apps only paste a TIFF.
        board.declareTypes([.png, .tiff], owner: nil)
        board.setData(png, forType: .png)
        board.setData(NSImage(data: png)?.tiffRepresentation, forType: .tiff)
    }

    static func save(_ png: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "seshka.png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    /// The picture as a file, which is what the system's share menu takes.
    static func file(_ png: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seshka.png")
        return (try? png.write(to: url)) == nil ? nil : url
    }
}

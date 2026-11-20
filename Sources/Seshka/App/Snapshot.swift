import AppKit
import SwiftUI

/// Draws the app's views into PNG files, to check a change without clicking through the app.
@MainActor
enum Snapshot {
    static var folder: String?

    static func run(store: Store, updater: Updater) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            // The first scan.
            try? await Task.sleep(for: .seconds(4))
            // The tour points at the menu bar item and opens it at the end. Both depend on finding it.
            let item = Welcome.menuBarButton
            print("menu bar item: \(item?.window.map { "found at \(Int($0.frame.midX)), \(Int($0.frame.midY))" } ?? "NOT FOUND")")
            item?.performClick(nil)
            try? await Task.sleep(for: .seconds(1))
            let menu = NSApp.windows.first { $0.isVisible && $0.frame.width == 480 }
            print("menu opens on a click: \(menu == nil ? "NO" : "yes")")
            item?.performClick(nil)
            fflush(stdout)
            let tabs: [(String, ContentView.Tab)] = [("leftover", .orphans), ("sessions", .sessions), ("settings", .settings), ("about", .about)]
            for (name, tab) in tabs {
                await save(ContentView(tab: tab).environmentObject(store).environmentObject(updater),
                           size: CGSize(width: 480, height: 600), to: "\(folder)/\(name).png")
            }
            // The menu as it looks while an update waits for a restart.
            updater.announces = false
            updater.pretend(version: "9.9.9")
            await save(ContentView(tab: .orphans).environmentObject(store).environmentObject(updater),
                       size: CGSize(width: 480, height: 600), to: "\(folder)/update.png")
            updater.pretend(version: nil)
            for page in 0..<5 {
                await save(WelcomeView(finish: { _ in }, page: page).environmentObject(store),
                           size: WelcomeView.size, to: "\(folder)/welcome-\(page + 1).png")
            }
            // What was cleaned up lately, and the picture made of it, with made-up numbers.
            let real = store.history
            store.pretend(history: .sample)
            await save(ContentView(tab: .about).environmentObject(store).environmentObject(updater),
                       size: CGSize(width: 480, height: 600), to: "\(folder)/about-week.png")
            await save(CleanView(title: "No leftover processes", detail: "Nothing started by a closed Claude Code session is still running.")
                .padding(30).environmentObject(store), size: CGSize(width: 480, height: 400), to: "\(folder)/clean-week.png")
            await save(ShareView(tally: store.history.week(), period: store.history.period()), size: ShareView.size, to: "\(folder)/share.png")
            // The file itself, made the way the buttons make it.
            try? Share.png(store.history.week(), period: store.history.period())?.write(to: URL(fileURLWithPath: "\(folder)/share-card.png"))
            try? Share.png(History.Tally(processes: 1284, sessions: 131, memory: 137_900_000_000, disk: 214_600_000_000), period: "since Wednesday")?
                .write(to: URL(fileURLWithPath: "\(folder)/share-card-large.png"))
            try? Share.png(History.Tally(disk: 6_800_000_000), period: "today")?.write(to: URL(fileURLWithPath: "\(folder)/share-card-disk.png"))
            store.pretend(history: real)
            // The Disk tab last, twice: a few seconds in, and once everything is measured, which can take minutes.
            let started = Date()
            store.refreshDisk()
            await save(ContentView(tab: .disk).environmentObject(store).environmentObject(updater),
                       size: CGSize(width: 480, height: 600), to: "\(folder)/disk-early.png")
            for _ in 0..<900 where store.diskRead == nil {
                try? await Task.sleep(for: .milliseconds(500))
            }
            print("disk measured in \(Int(Date().timeIntervalSince(started))) s")
            await save(ContentView(tab: .disk).environmentObject(store).environmentObject(updater),
                       size: CGSize(width: 480, height: 600), to: "\(folder)/disk.png")
            exit(0)
        }
    }

    private static func save<Content: View>(_ content: Content, size: CGSize, to file: String) async {
        // Far off the screen, so nothing flashes in front of whoever is working.
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        // The menu's own window is not there to give the views a background.
        window.contentView = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        window.orderFrontRegardless()
        // Long enough for the opening animations to settle.
        try? await Task.sleep(for: .seconds(2.5))
        if let view = window.contentView, let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
        }
        window.orderOut(nil)
    }
}

private extension History {
    /// A busy week, for drawing.
    static var sample: History {
        var history = History()
        let day = 86400.0
        history.add(Tally(processes: 9, sessions: 3, automatic: 3, memory: 9_400_000_000), on: Date().addingTimeInterval(-9 * day))
        history.add(Tally(processes: 27, memory: 6_013_000_000), on: Date().addingTimeInterval(-5 * day))
        history.add(Tally(processes: 4, sessions: 7, automatic: 5, memory: 21_300_000_000, disk: 8_900_000_000), on: Date().addingTimeInterval(-2 * day))
        history.add(Tally(processes: 11, sessions: 5, automatic: 2, memory: 14_100_000_000, disk: 6_800_000_000))
        return history
    }
}

import AppKit
import SwiftUI

@main
struct SeshkaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: Store
    @StateObject private var updater: Updater

    init() {
        // Command-line mode, used for testing the scan and kill logic without the UI:
        //   Seshka --list         print what the menu would show
        //   Seshka --kill <pid>   run the same kill routine the buttons use
        let args = CommandLine.arguments
        //   Seshka --kill-session <pid>   end an open session the way the Sessions tab does
        //   Seshka --disk         print what the Disk tab would offer to remove; removes nothing
        //   Seshka --remove <id>  run the same removal the Disk tab's buttons use, on a worktree or scratch item
        //   Seshka --list-after <seconds>   watch what open sessions start for that long, then print as --list does
        if args.count >= 2, ["--list", "--list-after", "--kill", "--kill-session", "--disk", "--remove"].contains(args[1]) {
            CLI.run(Array(args.dropFirst()))
            exit(0)
        }
        //   Seshka --render-logo <file.png>   draw the animated logo at six stages, for checking it
        if args.count == 3, args[1] == "--render-logo" {
            let strip = HStack(spacing: 12) {
                ForEach([0.0, 0.05, 0.12, 0.25, 0.6, 1.0], id: \.self) { stage in
                    Matryoshka(openness: stage).frame(width: 200, height: 200)
                }
            }
            .padding(12)
            .background(Color(red: 1, green: 0.91, blue: 0.78))
            let renderer = ImageRenderer(content: strip)
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[2]))
            }
            exit(0)
        }
        //   Seshka --snapshot <folder>   draw every tab and every page of the tour into PNG files, then quit
        if args.count == 3, args[1] == "--snapshot" {
            Snapshot.folder = args[2]
        }
        let store = Store()
        // Before its first scan ends: a copy that draws pictures leaves the Mac's sleep alone.
        if Snapshot.folder != nil { store.pretend(awake: .off) }
        let updater = Updater()
        //   Seshka --pretend-update <version>   behave as if that version had just been downloaded
        if args.count == 3, args[1] == "--pretend-update" {
            updater.pretend(version: args[2])
        }
        AppDelegate.store = store
        AppDelegate.updater = updater
        _store = StateObject(wrappedValue: store)
        _updater = StateObject(wrappedValue: updater)
        // Menu bar only: no Dock icon even when run outside an app bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .environmentObject(updater)
        } label: {
            Image(nsImage: store.orphanCount > 0 ? Icon.menuBarOpen : Icon.menuBarClosed)
            if store.orphanCount > 0 {
                Text("\(store.orphanCount)")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Opens the tour on a first run. A menu bar app has no scene that appears at launch to do it from.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var store: Store?
    @MainActor static var updater: Updater?
    private var termination: DispatchSourceSignal?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let store = Self.store, let updater = Self.updater else { return }
        // `kill` ends an app without a word. Taken as a request to quit instead, so that what is done
        // on the way out still gets done.
        signal(SIGTERM, SIG_IGN)
        termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination?.setEventHandler { NSApp.terminate(nil) }
        termination?.resume()
        UpdateDot.follow(updater, store)
        if Snapshot.folder != nil {
            Snapshot.run(store: store, updater: updater)
        } else if Welcome.isDue || CommandLine.arguments.contains("--welcome") {
            //   Seshka --welcome   show the tour again, whether or not it has been seen
            Welcome.show(store: store)
        }
    }

    /// Sleep that seshka switched off goes back on with it. Nobody would be there to do it later.
    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        Self.store?.releaseSleep(sleeping: false)
    }
}

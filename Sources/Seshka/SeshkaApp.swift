import AppKit
import SwiftUI

@main
struct SeshkaApp: App {
    @StateObject private var store: Store
    @StateObject private var updater: Updater

    init() {
        // Command-line mode, used for testing the scan and kill logic without the UI:
        //   Seshka --list         print what the menu would show
        //   Seshka --kill <pid>   run the same kill routine the buttons use
        let args = CommandLine.arguments
        //   Seshka --kill-session <pid>   end an open session the way the Sessions tab does
        if args.count >= 2, args[1] == "--list" || args[1] == "--kill" || args[1] == "--kill-session" {
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
        _store = StateObject(wrappedValue: Store())
        _updater = StateObject(wrappedValue: Updater())
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

enum CLI {
    static func run(_ args: [String]) {
        let procs = Scanner.scan()
        switch args[0] {
        case "--list":
            let orphans = Scanner.group(procs.filter { !$0.sessionAlive })
            let live = Scanner.group(procs.filter { $0.sessionAlive })
            print("orphans: \(orphans.reduce(0) { $0 + $1.procs.count }), \(formatBytes(orphans.reduce(0) { $0 + $1.memory }))")
            dump(orphans)
            print("live: \(live.reduce(0) { $0 + $1.procs.count })")
            dump(live)
            let sessions = Scanner.sessions(procs: procs)
            print("sessions: \(sessions.count)")
            for s in sessions {
                let state: String
                switch s.status {
                case .busy: state = "working"
                case .idle: state = "idle \(s.idleSeconds().map(humanAge) ?? "?")"
                case .other(let name): state = name
                case .unknown: state = "unknown"
                }
                print("  \(s.process.pid)\t\(state)\topen \(humanAge(s.process.age))\t\(formatBytes(s.memory))\t\(s.procs.count) bg\t\(s.title ?? s.project)")
            }
        case "--kill":
            guard args.count == 2, let pid = Int32(args[1]),
                  let proc = procs.first(where: { $0.pid == pid }) else {
                print("not a Claude Code process: \(args.dropFirst().joined(separator: " "))")
                exit(1)
            }
            let forced = Killer.terminate([proc])
            let gone = !Killer.isRunning(pid)
            print("pid \(pid): \(gone ? "gone, freed \(formatBytes(proc.memory))" : "STILL RUNNING") (\(forced.isEmpty ? "exited on SIGTERM" : "needed SIGKILL"))")
        case "--kill-session":
            guard args.count == 2, let pid = Int32(args[1]),
                  let session = Scanner.sessions(procs: procs).first(where: { $0.process.pid == pid }) else {
                print("not an open Claude Code session: \(args.dropFirst().joined(separator: " "))")
                exit(1)
            }
            Killer.terminate([session.process] + session.procs)
            print("session \(pid): \(Killer.isRunning(pid) ? "STILL RUNNING" : "ended, freed \(formatBytes(session.memory))")")
        default:
            break
        }
    }

    private static func dump(_ groups: [SessionGroup]) {
        for group in groups {
            print("  \(group.project) · \(group.shortID) · \(group.title ?? "-")")
            for p in group.procs {
                let ports = p.ports.map { ":" + $0 }.joined(separator: " ")
                print("    \(p.pid)\t\(humanAge(p.age))\t\(formatBytes(p.memory))\t\(ports)\t\(p.shortCommand.prefix(60))")
            }
        }
    }
}

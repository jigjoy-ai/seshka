import Foundation

enum CLI {
    static func run(_ args: [String]) {
        if args[0] == "--disk" {
            let context = Disk.context()
            var items = Disk.worktrees(context) + Disk.cachesFound()
            for i in items.indices {
                items[i].bytes = Disk.size(of: items[i].paths)
            }
            for item in items + Disk.scratch(context) where item.kind != .cache || (item.bytes ?? 0) >= Disk.smallestCache {
                let state: String
                switch item.state {
                case .removable: state = "removable"
                case .uncommitted: state = "uncommitted, to the Trash"
                case .busy(let reason): state = "in use: \(reason)"
                }
                print("\(item.kind)\t\(formatBytes(item.bytes ?? 0))\t\(item.title)\t\(item.detail)\t\(state)\t\(item.id)")
            }
            return
        }
        if args[0] == "--remove" {
            let context = Disk.context()
            guard args.count == 2, let item = (Disk.worktrees(context) + Disk.scratch(context)).first(where: { $0.id == args[1] }) else {
                print("not a worktree or scratch item of --disk: \(args.dropFirst().joined(separator: " "))")
                exit(1)
            }
            print(Disk.remove(item, context).map { "not removed: \($0)" } ?? "removed \(item.title)")
            return
        }
        if args[0] == "--list-after" {
            // The first scan starts the watch on open sessions. What they start while this waits is remembered.
            _ = Scanner.scan()
            Thread.sleep(forTimeInterval: args.count == 2 ? Double(args[1]) ?? 10 : 10)
        }
        let procs = Scanner.scan()
        switch args[0] {
        case "--list", "--list-after":
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
            let place = group.worktree.map { " · worktree \($0.label)\($0.missing ? " (folder gone)" : "")" } ?? ""
            print("  \(group.project) · \(group.shortID) · \(group.title ?? "-")\(place)")
            for p in group.procs {
                let ports = p.ports.map { ":" + $0 }.joined(separator: " ")
                let helpers = p.helpers.isEmpty ? "" : " (+\(p.helpers.count) helpers)"
                print("    \(p.pid)\t\(humanAge(p.age))\t\(formatBytes(p.memory))\t\(ports)\t\(p.shortCommand.prefix(60))\(helpers)")
            }
        }
    }
}

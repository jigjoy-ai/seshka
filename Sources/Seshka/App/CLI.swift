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
        if args[0] == "--leftovers" || args[0] == "--clean" {
            leftovers(args)
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
                if let back = Resumable(s) { print("  resume in \(back.terminal ?? "the default terminal"): \(back.command)") }
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
            if gone { CleanupLog.note(Cleanup(reason: .command, items: [Cleanup.Item(proc, place: place(of: proc, in: procs))])) }
        case "--kill-session":
            guard args.count == 2, let pid = Int32(args[1]),
                  let session = Scanner.sessions(procs: procs).first(where: { $0.process.pid == pid }) else {
                print("not an open Claude Code session: \(args.dropFirst().joined(separator: " "))")
                exit(1)
            }
            Killer.terminate([session.process] + session.procs)
            print("session \(pid): \(Killer.isRunning(pid) ? "STILL RUNNING" : "ended, freed \(formatBytes(session.memory))")")
            let name = session.title ?? session.project
            CleanupLog.note(Cleanup(reason: .command, items: ([session.process] + session.procs).filter { !Killer.isRunning($0.pid) }
                .map { Cleanup.Item($0, place: name, session: $0.pid == pid) }))
        default:
            break
        }
    }

    /// What the plugin's commands run: the leftover processes in words, and killing them.
    private static func leftovers(_ args: [String]) {
        // --here is the folder the command is run from: no path to quote, which Claude Code's own checks trip over.
        let folder = args.count == 3 && args[1] == "--in" ? args[2]
            : args.count == 2 && args[1] == "--here" ? FileManager.default.currentDirectoryPath : nil
        let groups = Leftovers.inside(folder, Scanner.group(Scanner.scan().filter { !$0.sessionAlive }))
        let procs = groups.flatMap(\.procs)
        let place = folder.map { " in \(Disk.abbreviate($0))" } ?? ""
        guard !procs.isEmpty else {
            print("Nothing is left running by closed Claude Code sessions\(place).")
            return
        }
        guard args[0] == "--clean" else {
            print("\(procs.count) process\(procs.count == 1 ? "" : "es") left running by closed Claude Code sessions\(place), \(formatBytes(procs.reduce(0) { $0 + $1.memory })) in all:")
            for group in groups {
                for proc in group.procs { print("- " + Leftovers.line(proc, of: group)) }
            }
            return
        }
        // The same list of protected commands the app keeps, read from its settings.
        let protected = (UserDefaults.standard.stringArray(forKey: "protectedPatterns") ?? ["limactl"]).map { $0.lowercased() }
        let (kept, targets) = procs.reduce(into: ([Proc](), [Proc]())) { result, proc in
            if protected.contains(where: { !$0.isEmpty && proc.command.lowercased().contains($0) }) { result.0.append(proc) } else { result.1.append(proc) }
        }
        Killer.terminate(targets)
        let gone = targets.filter { !Killer.isRunning($0.pid) }
        let freed = gone.reduce(UInt64(0)) { $0 + $1.memory }
        print("Killed \(gone.count) of \(targets.count) process\(targets.count == 1 ? "" : "es")\(place), \(formatBytes(freed)) of memory back.")
        for proc in targets where Killer.isRunning(proc.pid) { print("- still running: pid \(proc.pid) \(proc.shortCommand)") }
        for proc in kept { print("- protected, left alone: pid \(proc.pid) \(proc.shortCommand)") }
        // Counted with what the app itself cleaned up.
        if !gone.isEmpty {
            var history = History.load()
            history.add(History.Tally(processes: gone.count, memory: freed))
            history.save()
            // And written down with the reason, next to what the app itself killed.
            let dead = Set(gone.map(\.pid))
            CleanupLog.note(Cleanup(reason: .command, items: groups.flatMap { group in
                group.procs.filter { dead.contains($0.pid) }.map { Cleanup.Item($0, place: group.title ?? group.project) }
            }))
        }
    }

    /// The session a process belonged to, by its title, the way the log names it.
    private static func place(of proc: Proc, in procs: [Proc]) -> String {
        let group = Scanner.group(procs.filter { $0.sessionID == proc.sessionID && $0.sessionAlive == proc.sessionAlive })
            .first { $0.procs.contains { $0.pid == proc.pid } }
        return group.map { $0.title ?? $0.project } ?? (proc.cwd as NSString).lastPathComponent
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

import Foundation

/// Writing down what was killed and why. The log itself is in Log/CleanupLog.swift.
extension Store {
    /// The name each of these goes under in the log: its session's title, or the project. Looked up
    /// before the kill, while the lists still have them.
    func places(of procs: [Proc]) -> [Int32: String] {
        var bySession: [String: String] = [:]
        for group in orphans + live { bySession[group.sessionID] = group.title ?? group.project }
        var places: [Int32: String] = [:]
        for session in sessions {
            let name = session.title ?? session.project
            places[session.process.pid] = name
            for proc in session.procs { places[proc.pid] = name }
            if let id = session.sessionID { bySession[id] = name }
        }
        for proc in procs where places[proc.pid] == nil {
            places[proc.pid] = bySession[proc.sessionID] ?? (proc.cwd as NSString).lastPathComponent
        }
        return places
    }

    /// `sessions` are the ones among `gone` that were the Claude Code process of an open session.
    func note(_ gone: [Proc], reason: Cleanup.Reason, sessions: Set<Int32>, places: [Int32: String]) {
        guard !gone.isEmpty else { return }
        let items = gone.map { Cleanup.Item($0, place: places[$0.pid] ?? "", session: sessions.contains($0.pid)) }
        log = CleanupLog.note(Cleanup(reason: reason, detail: reason == .idleAutomatic ? formatLimit(idleLimitMinutes) : nil, items: items))
    }

    /// What is on disk now: the command line may have written since.
    func reloadLog() {
        guard !logPretended else { return }
        let latest = CleanupLog.load()
        if latest != log { log = latest }
    }

    func clearLog() {
        log = CleanupLog()
        log.save()
    }

    /// Shows a made-up log, for drawing. Nothing is written.
    func pretend(log: CleanupLog) {
        logPretended = true
        self.log = log
    }
}

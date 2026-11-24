import Foundation

/// Cleaning up after a session the moment it ends, on the word of the Claude Code plugin.
///
/// Without the plugin seshka finds leftovers by looking, and the user kills them. With it, Claude Code
/// says which session has just ended, and seshka kills what that session left running. Off until the
/// user turns it on.
extension Store {
    struct EndClean: Equatable {
        let count: Int
        let title: String
        let date: Date
    }

    func watchEnded() {
        endWatch = Ended.watch { [weak self] in
            Task { @MainActor in self?.heardEnded() }
        }
        // What was announced while seshka was not running.
        heardEnded()
    }

    private func heardEnded() {
        let pending = Ended.pending()
        let new = pending.keys.filter { !endedHeard.contains($0) }
        endedHeard = Set(pending.keys)
        guard !new.isEmpty else { return }
        pluginHeard = Date()
        guard cleansEndedSessions else {
            new.forEach(Ended.settle)
            return
        }
        // What the session started only loses it once Claude Code is gone, a moment after the hook ran.
        for delay in [2.0, 6.0, 14.0] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.refresh()
            }
        }
    }

    /// After every scan: kills what the sessions the plugin announced have left running.
    func sweepEnded() {
        for (session, announced) in Ended.pending() {
            // Two minutes is long enough for whatever the session left to have shown up.
            if !cleansEndedSessions || Date().timeIntervalSince(announced) > 120 {
                Ended.settle(session)
                continue
            }
            // Only what has lost its session: one that goes on in the same Claude Code process keeps what it runs.
            let groups = orphans.filter { $0.sessionID == session }
            let left = groups.flatMap(\.procs).filter { !isProtected($0) && !killing.contains($0.pid) }
            guard !left.isEmpty else { continue }
            lastEndClean = EndClean(count: left.count, title: groups.first.map { $0.title ?? $0.project } ?? "a session", date: Date())
            kill(left)
        }
    }
}

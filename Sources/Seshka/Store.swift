import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var orphans: [SessionGroup] = []
    @Published private(set) var live: [SessionGroup] = []
    /// Every open Claude Code session, the longest idle first.
    @Published private(set) var sessions: [RunningSession] = []
    @Published private(set) var killing: Set<Int32> = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var scanning = false
    /// What the most recent kills released; shown for a few seconds afterwards.
    @Published private(set) var freed: Freed?

    struct Freed: Equatable {
        var bytes: UInt64
        var count: Int
        var stamp = Date()
    }

    /// Commands containing any of these are never touched by "kill session" or "kill all".
    @Published var protectedPatterns: [String] {
        didSet { UserDefaults.standard.set(protectedPatterns, forKey: Keys.protected) }
    }

    /// A session waiting for input this long counts as idle, and "Kill idle" takes it. Never under half an hour.
    @Published var idleLimitMinutes: Int {
        didSet {
            if idleLimitMinutes < Store.minimumIdleLimit {
                idleLimitMinutes = Store.minimumIdleLimit
                return
            }
            UserDefaults.standard.set(idleLimitMinutes, forKey: Keys.idleLimit)
        }
    }
    static let minimumIdleLimit = 30

    /// While on, sessions idle past the limit are ended without asking, on every scan. Off unless the user turns it on.
    @Published var endsIdleSessions: Bool {
        didSet {
            UserDefaults.standard.set(endsIdleSessions, forKey: Keys.endsIdle)
            if endsIdleSessions { refresh() }
        }
    }

    /// The last time idle sessions were ended automatically, shown so it is never a mystery where one went.
    @Published private(set) var lastAutoEnd: AutoEnd?

    struct AutoEnd: Equatable {
        let count: Int
        let date: Date
    }

    @Published var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: Keys.interval)
            startTimer()
        }
    }

    /// In live sessions, hide processes younger than this; those are ordinary tool calls.
    private let minLiveAge = 60
    private var timer: Timer?
    private var rescanWhenDone = false

    static let listAnimation = Animation.easeInOut(duration: 0.6)

    private enum Keys {
        static let protected = "protectedPatterns"
        static let interval = "refreshInterval"
        static let idleLimit = "idleLimitMinutes"
        static let endsIdle = "endsIdleSessions"
    }

    init() {
        let defaults = UserDefaults.standard
        protectedPatterns = defaults.stringArray(forKey: Keys.protected) ?? ["limactl"]
        let saved = defaults.integer(forKey: Keys.interval)
        interval = saved > 0 ? saved : 30
        let limit = defaults.integer(forKey: Keys.idleLimit)
        idleLimitMinutes = limit > 0 ? max(limit, Store.minimumIdleLimit) : 120
        endsIdleSessions = defaults.bool(forKey: Keys.endsIdle)
        startTimer()
        refresh()
    }

    var orphanCount: Int { orphans.reduce(0) { $0 + $1.procs.count } }
    /// Sessions that have been waiting for input longer than the limit.
    var idleSessions: [RunningSession] {
        sessions.filter { ($0.idleSeconds() ?? -1) >= idleLimitMinutes * 60 }
    }
    var orphanMemory: UInt64 { orphans.reduce(0) { $0 + $1.memory } }

    /// Orphans that "kill all" would actually kill.
    var killableOrphans: [Proc] {
        orphans.flatMap(\.procs).filter { !isProtected($0) }
    }

    func isProtected(_ proc: Proc) -> Bool {
        let command = proc.command.lowercased()
        return protectedPatterns.contains { !$0.isEmpty && command.contains($0.lowercased()) }
    }

    func protect(_ proc: Proc) {
        let name = proc.executable
        if !protectedPatterns.contains(name) { protectedPatterns.append(name) }
    }

    func unprotect(_ proc: Proc) {
        let command = proc.command.lowercased()
        protectedPatterns.removeAll { command.contains($0.lowercased()) }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !scanning else {
            // A scan is already running and may predate a kill; run another when it ends.
            rescanWhenDone = true
            return
        }
        scanning = true
        let minLiveAge = self.minLiveAge
        Task.detached(priority: .utility) {
            let procs = Scanner.scan()
            let orphans = Scanner.group(procs.filter { !$0.sessionAlive })
            let sessions = Scanner.sessions(procs: procs)
                .sorted { ($0.idleSeconds() ?? -1, $0.process.age) > ($1.idleSeconds() ?? -1, $1.process.age) }
            // Background processes whose session could not be matched to an open one still get listed.
            let matched = Set(sessions.compactMap(\.sessionID))
            let live = Scanner.group(procs.filter { $0.sessionAlive && $0.age >= minLiveAge && !matched.contains($0.sessionID) })
            await MainActor.run {
                withAnimation(Store.listAnimation) {
                    self.orphans = orphans
                    self.live = live
                    self.sessions = sessions
                }
                self.lastScan = Date()
                self.scanning = false
                if self.endsIdleSessions {
                    // Sessions already being ended are not counted again.
                    let due = self.idleSessions.filter { !self.killing.contains($0.process.pid) }
                    if !due.isEmpty {
                        self.lastAutoEnd = AutoEnd(count: due.count, date: Date())
                        self.killIdleSessions()
                    }
                }
                if self.rescanWhenDone {
                    self.rescanWhenDone = false
                    self.refresh()
                }
            }
        }
    }

    func kill(_ procs: [Proc]) {
        let targets = procs.filter { !killing.contains($0.pid) }
        guard !targets.isEmpty else { return }
        killing.formUnion(targets.map(\.pid))
        Task.detached(priority: .userInitiated) {
            Killer.terminate(targets)
            let gone = targets.filter { !Killer.isRunning($0.pid) }
            let bytes = gone.reduce(UInt64(0)) { $0 + $1.memory }
            await MainActor.run {
                self.killing.subtract(targets.map(\.pid))
                if !gone.isEmpty { self.announceFreed(bytes: bytes, count: gone.count) }
                // Take the dead ones off the list right away; the rescan then confirms it.
                let pids = Set(gone.map(\.pid))
                withAnimation(Store.listAnimation) {
                    self.orphans = Store.removing(pids, from: self.orphans)
                    self.live = Store.removing(pids, from: self.live)
                    self.sessions.removeAll { pids.contains($0.process.pid) }
                    for i in self.sessions.indices {
                        self.sessions[i].procs.removeAll { pids.contains($0.pid) }
                    }
                }
                self.refresh()
            }
        }
    }

    private static func removing(_ pids: Set<Int32>, from groups: [SessionGroup]) -> [SessionGroup] {
        groups.compactMap { group in
            var group = group
            group.procs.removeAll { pids.contains($0.pid) }
            return group.procs.isEmpty ? nil : group
        }
    }

    /// Kills made in quick succession add up into one message.
    private func announceFreed(bytes: UInt64, count: Int) {
        let message = Freed(bytes: (freed?.bytes ?? 0) + bytes, count: (freed?.count ?? 0) + count)
        freed = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            if self.freed == message { self.freed = nil }
        }
    }

    /// Kills everything in a session except protected processes.
    func kill(session: SessionGroup) {
        kill(session.procs.filter { !isProtected($0) })
    }

    func killAllOrphans() {
        kill(killableOrphans)
    }

    /// Ends a session: the Claude Code process and what it has running, except protected processes.
    /// The conversation itself is not lost; `claude --resume` brings it back.
    func kill(running session: RunningSession) {
        kill([session.process] + session.procs.filter { !isProtected($0) })
    }

    func killIdleSessions() {
        kill(idleSessions.flatMap { [$0.process] + $0.procs.filter { !isProtected($0) } })
    }

    // MARK: - Launch at login

    var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message on failure.
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            objectWillChange.send()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func formatBytes(_ bytes: UInt64) -> String {
    let mb = Double(bytes) / 1_048_576
    if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
    if mb >= 1 { return String(format: "%.0f MB", mb) }
    return bytes == 0 ? "–" : "<1 MB"
}

/// "30 min", "2 h", "2 h 30 min".
func formatLimit(_ minutes: Int) -> String {
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return "\(rest) min" }
    return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
}

func humanAge(_ seconds: Int) -> String {
    if seconds >= 86400 { return "\(seconds / 86400)d" }
    if seconds >= 3600 { return "\(seconds / 3600)h" }
    if seconds >= 60 { return "\(seconds / 60)m" }
    return "\(seconds)s"
}

import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class Store: ObservableObject {
    @Published private(set) var orphans: [SessionGroup] = []
    @Published private(set) var live: [SessionGroup] = []
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
    }

    init() {
        let defaults = UserDefaults.standard
        protectedPatterns = defaults.stringArray(forKey: Keys.protected) ?? ["limactl"]
        let saved = defaults.integer(forKey: Keys.interval)
        interval = saved > 0 ? saved : 30
        startTimer()
        refresh()
    }

    var orphanCount: Int { orphans.reduce(0) { $0 + $1.procs.count } }
    var liveCount: Int { live.reduce(0) { $0 + $1.procs.count } }
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
            let live = Scanner.group(procs.filter { $0.sessionAlive && $0.age >= minLiveAge })
            await MainActor.run {
                withAnimation(Store.listAnimation) {
                    self.orphans = orphans
                    self.live = live
                }
                self.lastScan = Date()
                self.scanning = false
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

func humanAge(_ seconds: Int) -> String {
    if seconds >= 86400 { return "\(seconds / 86400)d" }
    if seconds >= 3600 { return "\(seconds / 3600)h" }
    if seconds >= 60 { return "\(seconds / 60)m" }
    return "\(seconds)s"
}

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

    /// What could be removed from disk. Read when the Disk tab asks, not on every scan: measuring
    /// folders takes a while.
    @Published private(set) var disk: [DiskItem] = []
    @Published private(set) var diskScanning = false
    @Published private(set) var diskRead: Date?
    /// Items being removed right now.
    @Published private(set) var removing: Set<String> = []
    /// What the removals of this run released.
    @Published private(set) var diskFreed: UInt64 = 0
    /// Why the last removal failed, with the item it was about.
    @Published var diskFailure: DiskFailure?
    private var rereadDiskWhenDone = false
    private var removedDuringScan: Set<String> = []

    struct DiskFailure: Equatable {
        let id: String
        let reason: String
    }

    /// What has been cleaned up so far, day by day. Kept on disk.
    @Published private(set) var history = History.load()

    // Staying awake with the lid closed. The rules are in Store+Awake.swift.

    /// While on, the Mac is kept from sleeping for as long as a session is working, lid closed or not.
    /// Turned on through `setStaysAwake`, which asks for the permission it needs.
    @Published var staysAwake: Bool {
        didSet { UserDefaults.standard.set(staysAwake, forKey: Keys.staysAwake) }
    }
    /// On battery, staying awake stops below this many percent.
    @Published var awakeBatteryFloor: Int {
        didSet {
            UserDefaults.standard.set(awakeBatteryFloor, forKey: Keys.awakeFloor)
            updateAwake()
        }
    }
    @Published var awake: Awake = .off
    /// Why sleep could not be switched, when it could not.
    @Published var awakeFailure: String?
    /// The last time a session was seen working.
    var lastWorking: Date?
    /// Keeps macOS from slowing seshka's timers down while it is the one holding the Mac awake.
    var awakeActivity: NSObjectProtocol?
    var awakeTimer: Timer?
    /// Whether the lid was closed the last time seshka looked, to turn the screen off once when it closes.
    var lidWasClosed = false
    /// Set by the copy that only draws pictures: it shows whatever it is told and never switches sleep.
    var awakeFrozen = false

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
        static let disk = "diskItems"
        static let staysAwake = "staysAwake"
        static let awakeFloor = "awakeBatteryFloor"
    }

    init() {
        let defaults = UserDefaults.standard
        CommandWatch.shared.keeps = true
        protectedPatterns = defaults.stringArray(forKey: Keys.protected) ?? ["limactl"]
        let saved = defaults.integer(forKey: Keys.interval)
        interval = saved > 0 ? saved : 30
        let limit = defaults.integer(forKey: Keys.idleLimit)
        idleLimitMinutes = limit > 0 ? max(limit, Store.minimumIdleLimit) : 120
        endsIdleSessions = defaults.bool(forKey: Keys.endsIdle)
        staysAwake = defaults.bool(forKey: Keys.staysAwake)
        let floor = defaults.integer(forKey: Keys.awakeFloor)
        awakeBatteryFloor = floor > 0 ? floor : 20
        // The list as it was last measured, kept between runs: measuring takes the better part of a
        // minute, and the Disk tab should have its rows and numbers the moment it opens.
        if let saved = defaults.data(forKey: Keys.disk), let items = try? JSONDecoder().decode([DiskItem].self, from: saved) {
            disk = items
        }
        if disk.isEmpty {
            // Never measured on this Mac. Start soon after launch, so the Disk tab has its numbers by
            // the time it is first opened. After that it measures only when the tab is opened.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                if self?.diskRead == nil { self?.refreshDisk() }
            }
        }
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
                self.updateAwake()
                if self.endsIdleSessions {
                    // Sessions already being ended are not counted again.
                    let due = self.idleSessions.filter { !self.killing.contains($0.process.pid) }
                    if !due.isEmpty {
                        self.lastAutoEnd = AutoEnd(count: due.count, date: Date())
                        self.killIdleSessions(automatic: true)
                    }
                }
                if self.rescanWhenDone {
                    self.rescanWhenDone = false
                    self.refresh()
                }
            }
        }
    }

    /// `sessions` are the ones among `procs` that are the Claude Code process of an open session.
    func kill(_ procs: [Proc], sessions: Set<Int32> = [], automatic: Bool = false) {
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
                let ended = gone.filter { sessions.contains($0.pid) }.count
                self.record(History.Tally(processes: gone.count - ended, sessions: ended, automatic: automatic ? ended : 0, memory: bytes))
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
        kill([session.process] + session.procs.filter { !isProtected($0) }, sessions: [session.process.pid])
    }

    func killIdleSessions(automatic: Bool = false) {
        let idle = idleSessions
        kill(idle.flatMap { [$0.process] + $0.procs.filter { !isProtected($0) } }, sessions: Set(idle.map(\.process.pid)), automatic: automatic)
    }

    // MARK: - History

    private func record(_ tally: History.Tally) {
        // Read again first: another copy of seshka may have written since.
        var latest = History.load()
        latest.add(tally)
        latest.save()
        history = latest
    }

    /// Shows a made-up history, for drawing the views that use it. Nothing is written.
    func pretend(history: History) {
        self.history = history
    }

    /// Shows a made-up state of staying awake, for drawing. Nothing on the Mac is switched.
    func pretend(awake: Awake) {
        awakeFrozen = true
        self.awake = awake
    }

    // MARK: - Disk

    /// Everything on the list that may be removed, largest first within its kind.
    func disk(_ kind: DiskItem.Kind) -> [DiskItem] {
        disk.filter { $0.kind == kind && (kind != .cache || ($0.bytes ?? 0) >= Disk.smallestCache) }
    }

    /// How much the items that may be removed take together.
    var diskRemovable: UInt64 {
        DiskItem.Kind.allCases.flatMap(disk).filter { if case .busy = $0.state { false } else { true } }
            .reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    func refreshDisk() {
        guard !diskScanning else {
            rereadDiskWhenDone = true
            return
        }
        diskScanning = true
        removedDuringScan = []
        Task.detached(priority: .utility) {
            let context = Disk.context()
            var items = Disk.worktrees(context) + Disk.cachesFound()
            // Until a row is measured again, it shows what it measured last time.
            let last = await self.disk
            let remembered = Dictionary(last.map { ($0.id, $0.bytes) }, uniquingKeysWith: { first, _ in first })
            for i in items.indices { items[i].bytes = remembered[items[i].id] ?? nil }
            var scratch = last.filter { $0.kind == .scratch }
            await self.show(items + scratch)

            // Several folders at a time: one after another, the last row waited minutes for its number.
            enum Measured {
                case scratch([DiskItem])
                case size(String, UInt64)
            }
            await withTaskGroup(of: Measured.self) { group in
                var next = 0
                func startNext(_ group: inout TaskGroup<Measured>) {
                    guard next < items.count else { return }
                    let item = items[next]
                    next += 1
                    group.addTask { .size(item.id, Disk.size(of: item.paths)) }
                }
                group.addTask { .scratch(Disk.scratch(context)) }
                for _ in 0..<4 { startNext(&group) }
                for await result in group {
                    switch result {
                    case .scratch(let found):
                        scratch = found
                    case .size(let id, let bytes):
                        if let i = items.firstIndex(where: { $0.id == id }) { items[i].bytes = bytes }
                        startNext(&group)
                    }
                    await self.show(items + scratch)
                }
            }
            await MainActor.run {
                self.diskScanning = false
                self.diskRead = Date()
                UserDefaults.standard.set(try? JSONEncoder().encode(self.disk), forKey: Keys.disk)
                if self.rereadDiskWhenDone {
                    self.rereadDiskWhenDone = false
                    self.refreshDisk()
                }
            }
        }
    }

    private func show(_ items: [DiskItem]) {
        // Worktrees and scratch files by size; caches too, once they have one.
        let sorted = items.enumerated().sorted { a, b in
            if a.element.kind != b.element.kind { return a.element.kind.rawValue < b.element.kind.rawValue }
            let x = a.element.bytes ?? 0, y = b.element.bytes ?? 0
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        // A scan that started before a removal still has the removed item on its list.
        withAnimation(Store.listAnimation) { disk = sorted.filter { !removedDuringScan.contains($0.id) } }
    }

    func remove(_ item: DiskItem) {
        guard !removing.contains(item.id) else { return }
        removing.insert(item.id)
        diskFailure = nil
        Task.detached(priority: .userInitiated) {
            let failure = Disk.remove(item, Disk.context())
            let left = Disk.size(of: item.paths)
            await MainActor.run {
                self.removing.remove(item.id)
                if let failure {
                    self.diskFailure = DiskFailure(id: item.id, reason: failure)
                }
                // A worktree that went to the Trash still takes its room until the Trash is emptied.
                let freed = (item.bytes ?? 0) > left ? (item.bytes ?? 0) - left : 0
                if item.state != .uncommitted {
                    self.diskFreed += freed
                    self.record(History.Tally(disk: freed))
                }
                withAnimation(Store.listAnimation) {
                    if left == 0 {
                        self.removedDuringScan.insert(item.id)
                        self.disk.removeAll { $0.id == item.id }
                    } else if let i = self.disk.firstIndex(where: { $0.id == item.id }) {
                        self.disk[i].bytes = left
                    }
                }
                self.refresh()
            }
        }
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

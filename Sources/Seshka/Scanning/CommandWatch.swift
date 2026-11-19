import Foundation

/// Remembers which process group each command of an open Claude Code session ran in.
///
/// Claude Code starts every command in a shell of its own, which leads a process group of its own.
/// Whatever the command starts stays in that group, also after the shell is gone and its parent is
/// launchd. For a process that hides its environment and sends its output elsewhere, the group is the
/// only thing left that says where it came from, and the group's number alone says nothing: it is the
/// PID of a shell that lived for a few milliseconds.
///
/// So the system is asked to say when a Claude Code process starts something, and the shell is noted
/// the moment it appears. Only groups seen being started this way are trusted. A group merely shared
/// with something of Claude Code's is not: a tool that runs Claude Code itself shares one with it.
final class CommandWatch {
    static let shared = CommandWatch()

    struct Command: Codable {
        let session: String
        /// The Claude Code process that started it.
        let claude: Int32
        /// A process of the group and when it started, to recognize the group again after seshka restarts.
        var witness: Int32 = 0
        var witnessStarted: Double = 0
        /// When the group was first seen.
        var noted: Double = Date().timeIntervalSince1970
    }

    /// Only the app keeps what it learned between runs. The command-line checks read it and leave it be.
    var keeps = false

    private static let key = "commandGroups"
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ai.jigjoy.seshka.command-watch")
    /// By process group.
    private var commands: [Int32: Command] = [:]
    /// Read from the last run, and not yet matched against what is running now.
    private var unchecked: [Int32: Command] = [:]
    /// The session of each Claude Code process being watched.
    private var sessions: [Int32: String] = [:]
    private var sources: [Int32: DispatchSourceProcess] = [:]

    private init() {
        if let saved = UserDefaults.standard.data(forKey: Self.key),
           let groups = try? JSONDecoder().decode([Int32: Command].self, from: saved) {
            unchecked = groups
        }
    }

    /// The command that started this process group, if it was seen starting.
    func command(ofGroup group: Int32) -> Command? {
        lock.lock()
        defer { lock.unlock() }
        return commands[group]
    }

    /// Watches these Claude Code processes, each with its session, and stops watching the ones that are gone.
    func watch(_ open: [Int32: String]) {
        lock.lock()
        sessions = open
        let gone = sources.filter { open[$0.key] == nil }
        for pid in gone.keys { sources[pid] = nil }
        let new = open.keys.filter { sources[$0] == nil }
        var added: [DispatchSourceProcess] = []
        for pid in new {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .fork, queue: queue)
            source.setEventHandler { [weak self] in self?.note(startedBy: pid) }
            sources[pid] = source
            added.append(source)
        }
        lock.unlock()
        gone.values.forEach { $0.cancel() }
        added.forEach { $0.resume() }
        // What a newly seen session already has running.
        for pid in new {
            queue.async { self.note(startedBy: pid) }
        }
    }

    /// Notes the groups this Claude Code process has just started: its children that lead a group.
    private func note(startedBy claude: Int32) {
        var children = [pid_t](repeating: 0, count: 1024)
        _ = proc_listchildpids(claude, &children, Int32(MemoryLayout<pid_t>.size * children.count))
        lock.lock()
        defer { lock.unlock() }
        guard let session = sessions[claude] else { return }
        for child in children where child > 0 && getpgid(child) == child && commands[child] == nil {
            commands[child] = Command(session: session, claude: claude)
        }
    }

    /// Brings what is remembered in line with what is running. `groups` is every process with its group,
    /// `ages` the seconds since each of the user's processes started.
    func settle(groups: [Int32: Int32], ages: [Int32: Int]) {
        let now = Date().timeIntervalSince1970
        var member: [Int32: Int32] = [:]
        for (pid, group) in groups where ages[pid] != nil {
            member[group] = min(member[group] ?? pid, pid)
        }
        lock.lock()
        // From the last run: kept only if the process that vouched for the group is still that process.
        // A PID is not handed out again while it is some group's number, so the group is the same too.
        for (group, command) in unchecked where commands[group] == nil {
            guard groups[command.witness] == group, let age = ages[command.witness],
                  abs(now - Double(age) - command.witnessStarted) <= 3 else { continue }
            commands[group] = command
        }
        unchecked = [:]
        // A group with nobody left in it is over, and its number is free to be anyone's. One noted a moment
        // ago may be newer than the list of processes it is checked against, so it is given a minute.
        commands = commands.filter { member[$0.key] != nil || now - $0.value.noted < 60 }
        for group in commands.keys {
            guard let pid = member[group], let age = ages[pid], commands[group]?.witness != pid else { continue }
            commands[group]?.witness = pid
            commands[group]?.witnessStarted = now - Double(age)
        }
        let saved = keeps ? try? JSONEncoder().encode(commands) : nil
        lock.unlock()
        if let saved { UserDefaults.standard.set(saved, forKey: Self.key) }
    }
}

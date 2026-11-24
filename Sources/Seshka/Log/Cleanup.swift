import Foundation

/// One clean-up: what seshka killed at one moment, and why. Written down so that it is never a
/// mystery where a process went, least of all when seshka acted on its own.
struct Cleanup: Codable, Identifiable, Equatable {
    enum Reason: String, Codable {
        /// Kill on one process.
        case click
        /// Kill on the card of a closed session.
        case session
        /// Kill all.
        case all
        /// Kill on an open session.
        case ended
        /// Kill idle, on a click.
        case idle
        /// A session idle past the limit, ended because the switch is on.
        case idleAutomatic
        /// The Claude Code plugin said the session ended, and the switch is on.
        case sessionEnded
        /// `seshka --clean` and its kind, which is also what /seshka:clean runs.
        case command

        /// Whether seshka did it without being asked at that moment.
        var automatic: Bool { self == .idleAutomatic || self == .sessionEnded }
    }

    struct Item: Codable, Identifiable, Equatable {
        var pid: Int32
        /// The command as the list showed it, cut short.
        var name: String
        var ports: [String]
        var memory: UInt64
        /// The session it belonged to, by its title, or the project when it had none.
        var place: String
        /// True for the Claude Code process of an open session: the session itself was ended.
        var session: Bool

        var id: Int32 { pid }

        init(_ proc: Proc, place: String, session: Bool = false) {
            pid = proc.pid
            name = session ? "Claude Code session" : String(proc.shortCommand.replacingOccurrences(of: "\n", with: " ").prefix(120))
            ports = proc.ports
            memory = proc.memory
            self.place = place
            self.session = session
        }

        init(pid: Int32, name: String, ports: [String] = [], memory: UInt64, place: String, session: Bool = false) {
            self.pid = pid
            self.name = name
            self.ports = ports
            self.memory = memory
            self.place = place
            self.session = session
        }
    }

    var id = UUID()
    var date = Date()
    var reason: Reason
    /// What the reason needs to be told in full: the idle limit at the time, "2 h".
    var detail: String?
    var items: [Item]

    var memory: UInt64 { items.reduce(0) { $0 + $1.memory } }
    var sessions: Int { items.filter(\.session).count }
    var processes: Int { items.count - sessions }

    /// The reason in words.
    var why: String {
        switch reason {
        case .click: "You killed it"
        case .session: "You killed what a closed session left"
        case .all: "You clicked Kill all"
        case .ended: "You ended the session"
        case .idle: "You ended the idle sessions"
        case .idleAutomatic: "Idle for over \(detail ?? "the limit"), ended automatically"
        case .sessionEnded: "Its session ended, killed automatically"
        case .command: "Killed from the command line or /seshka:clean"
        }
    }

    /// "2 processes · 1 session · 1.4 GB".
    var summary: String {
        var parts: [String] = []
        if processes > 0 { parts.append("\(processes) process\(processes == 1 ? "" : "es")") }
        if sessions > 0 { parts.append("\(sessions) session\(sessions == 1 ? "" : "s")") }
        if memory > 0 { parts.append(formatBytes(memory)) }
        return parts.joined(separator: "  ·  ")
    }
}

import Foundation

/// A process that was started by a Claude Code session.
struct Proc: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    /// Seconds since the process started.
    let age: Int
    let sessionID: String
    /// True while the Claude Code process that started it is still running.
    let sessionAlive: Bool
    /// Full command line, without the environment.
    let command: String
    var cwd: String = ""
    var ports: [String] = []
    /// Real memory use in bytes, the same number Activity Monitor shows as "Memory".
    var memory: UInt64 = 0

    /// Path of the executable. Unlike the command line it is unambiguous when the path has spaces.
    var path: String = ""
    /// Helper processes of the same app, folded into this row. Their memory and ports are counted here.
    var helpers: [Helper] = []
    /// The process group. Claude Code starts every command in a group of its own, and whatever that
    /// command starts stays in it, even after losing its parent.
    var group: Int32 = 0
    /// For the shell Claude Code wraps a command in: the command itself, shown instead of the wrapping.
    var wrapped: String?
    /// The git worktree the process runs in, when that is not the repository's main folder.
    var worktree: Worktree?

    struct Helper: Hashable {
        let pid: Int32
        let command: String
    }

    var id: Int32 { pid }

    /// The arguments, when the command line starts with the executable's path.
    private var arguments: Substring? {
        guard !path.isEmpty, command.hasPrefix(path) else { return nil }
        let rest = command.dropFirst(path.count)
        return rest.isEmpty || rest.hasPrefix(" ") ? rest : nil
    }

    var executable: String {
        let first = arguments != nil ? path : command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let name = (first as NSString).lastPathComponent
        return name == "Python" ? "python" : name
    }

    var shortCommand: String {
        if let wrapped { return wrapped }
        let text: String
        if let arguments {
            text = executable + arguments
        } else {
            let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
            text = parts.count > 1 ? executable + " " + parts[1] : executable
        }
        // ps prints newlines inside arguments as the octal escape \012
        return text.replacingOccurrences(of: "\\012", with: " ")
    }

    /// The app bundle this process is the main executable of, e.g. "/Applications/Google Chrome.app/".
    var bundleRoot: String? {
        guard let marker = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[..<marker.lowerBound]) + ".app/"
    }
}

/// What one session has running in one place: a card in the list. A session that worked in several
/// git worktrees gets a group for each, so it is plain which task left what behind.
struct SessionGroup: Identifiable {
    let id: String
    let sessionID: String
    let project: String
    let title: String?
    let worktree: Worktree?
    var procs: [Proc]

    var shortID: String { String(sessionID.prefix(8)) }
    var memory: UInt64 { procs.reduce(0) { $0 + $1.memory } }
    var oldest: Int { procs.map(\.age).max() ?? 0 }
}

/// A Claude Code session that is still open: the `claude` process and what it has running.
struct RunningSession: Identifiable {
    enum Status: Equatable {
        case busy
        case idle
        /// A status this version of seshka does not know.
        case other(String)
        /// Claude Code left no record for this process.
        case unknown
    }

    /// The `claude` process itself.
    let process: Proc
    let sessionID: String?
    let project: String
    let title: String?
    let status: Status
    /// When the session entered its current status.
    let statusSince: Date?
    /// Its background processes, older than a minute.
    var procs: [Proc]

    var id: Int32 { process.pid }
    var memory: UInt64 { process.memory + procs.reduce(0) { $0 + $1.memory } }

    /// How long the session has been waiting for input, or nil while it is working.
    func idleSeconds(now: Date = Date()) -> Int? {
        guard status == .idle, let since = statusSince else { return nil }
        return max(0, Int(now.timeIntervalSince(since)))
    }
}

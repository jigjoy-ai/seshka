import Foundation

/// A session seshka ended, kept for a while so it can be brought back with a click.
struct Resumable: Codable, Identifiable, Equatable {
    /// The session's ID, which is what `claude --resume` takes.
    let id: String
    let title: String
    let project: String
    /// The folder the session was started in. A session is resumed from there.
    let folder: String
    /// TERM_PROGRAM of the terminal it ran in, when that could be read.
    let terminal: String?
    let ended: Date

    /// Made while the session is still running: afterwards its terminal can no longer be asked.
    init?(_ session: RunningSession) {
        guard let id = session.sessionID, UUID(uuidString: id) != nil, !session.process.cwd.isEmpty else { return nil }
        self.id = id
        title = session.title ?? session.project
        project = session.project
        folder = session.process.cwd
        terminal = Scanner.environment("TERM_PROGRAM", of: session.process.pid)
        ended = Date()
    }

    /// A made-up one, for drawing.
    init(id: String, title: String, project: String, folder: String, ended: Date) {
        self.id = id
        self.title = title
        self.project = project
        self.folder = folder
        self.ended = ended
        terminal = nil
    }

    /// What to type to bring it back.
    var command: String {
        "cd \(Resumer.quoted(folder)) && claude --resume \(id)"
    }

    // MARK: - Kept between runs

    private static let key = "endedSessions"
    /// Long enough to cover a weekend, short enough that the list stays about now.
    private static let kept: TimeInterval = 3 * 86400
    private static let most = 8

    static func load() -> [Resumable] {
        guard let saved = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Resumable].self, from: saved) else { return [] }
        return trimmed(list)
    }

    static func save(_ list: [Resumable]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(trimmed(list)), forKey: key)
    }

    /// The newest first, one entry per session.
    static func trimmed(_ list: [Resumable]) -> [Resumable] {
        var seen = Set<String>()
        return list.sorted { $0.ended > $1.ended }
            .filter { Date().timeIntervalSince($0.ended) < kept && seen.insert($0.id).inserted }
            .prefix(most).map { $0 }
    }
}

extension Scanner {
    /// One variable of a process's environment, when macOS lets it be read.
    static func environment(_ name: String, of pid: Int32) -> String? {
        let line = Shell.run("/bin/ps", ["eww", "-p", String(pid), "-o", "command="])
        guard let found = line.range(of: " \(name)=") else { return nil }
        let value = line[found.upperBound...].prefix { $0 != " " && $0 != "\n" }
        return value.isEmpty ? nil : String(value)
    }
}

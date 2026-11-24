import Foundation

/// The clean-ups of the last two weeks, newest first. Kept in a file on this Mac and nowhere else.
/// Unlike the counts in History it holds names: the commands that were killed and the sessions they
/// belonged to. That is the point of it, and the reason it is short-lived and can be cleared.
struct CleanupLog: Codable, Equatable {
    private(set) var entries: [Cleanup] = []

    static let daysKept = 14
    private static let most = 300

    mutating func add(_ cleanup: Cleanup) {
        guard !cleanup.items.isEmpty else { return }
        entries.insert(cleanup, at: 0)
        let oldest = Date().addingTimeInterval(-Double(CleanupLog.daysKept) * 86400)
        entries = Array(entries.filter { $0.date >= oldest }.prefix(CleanupLog.most))
    }

    // MARK: - On disk

    static var file: URL {
        History.file.deletingLastPathComponent().appendingPathComponent("cleanups.json")
    }

    static func load() -> CleanupLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file), let log = try? decoder.decode(CleanupLog.self, from: data) else {
            return CleanupLog()
        }
        return log
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: CleanupLog.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: CleanupLog.file, options: .atomic)
        // Command lines are in it: readable by the user alone.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: CleanupLog.file.path)
    }

    /// Writes one clean-up down and returns the log as it then is. Read from disk first: the app and
    /// its command line both write here.
    @discardableResult
    static func note(_ cleanup: Cleanup) -> CleanupLog {
        var log = load()
        log.add(cleanup)
        log.save()
        return log
    }

    /// For drawing: a log that holds exactly these.
    static func made(of entries: [Cleanup]) -> CleanupLog {
        CleanupLog(entries: entries)
    }
}

import Foundation

/// What seshka has cleaned up, day by day. Numbers only: no names, commands or paths are kept, so
/// nothing made from it can show what someone works on.
struct History: Codable, Equatable {
    struct Tally: Codable, Equatable {
        /// Processes killed, not counting the Claude Code process of a session.
        var processes = 0
        /// Open sessions ended, on a click or automatically.
        var sessions = 0
        /// How many of those sessions were ended automatically.
        var automatic = 0
        /// The memory all of them held when they were killed.
        var memory: UInt64 = 0
        /// The room made on disk.
        var disk: UInt64 = 0

        var isEmpty: Bool { self == Tally() }

        static func + (a: Tally, b: Tally) -> Tally {
            Tally(processes: a.processes + b.processes, sessions: a.sessions + b.sessions, automatic: a.automatic + b.automatic,
                  memory: a.memory + b.memory, disk: a.disk + b.disk)
        }
    }

    /// One tally for each day that has something in it, under a key like "2026-11-20".
    private(set) var days: [String: Tally] = [:]
    /// Everything since the first day, including days that are no longer kept.
    private(set) var total = Tally()
    /// The first day anything was written down.
    private(set) var first: String?

    private static let daysKept = 90

    mutating func add(_ tally: Tally, on date: Date = Date()) {
        guard !tally.isEmpty else { return }
        let day = History.key(date)
        days[day] = (days[day] ?? Tally()) + tally
        total = total + tally
        first = first ?? day
        let oldest = History.key(date, back: History.daysKept)
        days = days.filter { $0.key >= oldest }
    }

    /// The last seven days, today included.
    func week(_ today: Date = Date()) -> Tally {
        (0..<7).reduce(Tally()) { sum, back in sum + (days[History.key(today, back: back)] ?? Tally()) }
    }

    /// The time `week` covers, in words: "today", "since Tuesday" or "in the last 7 days". Counting
    /// starts with the first clean-up, so until a week has passed it says since when.
    func period(_ today: Date = Date()) -> String {
        guard let first, first > History.key(today, back: 6), let start = History.dayFormat.date(from: first) else {
            return "in the last 7 days"
        }
        if first == History.key(today) { return "today" }
        return "since " + History.weekday.string(from: start)
    }

    // MARK: - On disk

    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seshka/history.json")
    }

    static func load() -> History {
        guard let data = try? Data(contentsOf: file), let history = try? JSONDecoder().decode(History.self, from: data) else {
            return History()
        }
        return history
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: History.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: History.file, options: .atomic)
    }

    private static let dayFormat = formatter("yyyy-MM-dd")
    private static let weekday = formatter("EEEE")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// The key of the day `back` days before `date`. By the calendar, so a day with a clock change is not skipped.
    private static func key(_ date: Date, back: Int = 0) -> String {
        dayFormat.string(from: Calendar.current.date(byAdding: .day, value: -back, to: date) ?? date)
    }
}

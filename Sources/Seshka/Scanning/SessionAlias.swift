import Foundation

/// Which session an old session ID goes by now.
///
/// A process carries the ID of the session it was started in for as long as it lives. The session may
/// have moved on to a new ID since. While the session is open that is plain to see: the process hangs
/// off a Claude Code process whose session is known. Once the session closes, the old ID is all that
/// is left, and nothing on disk says whose it was. So each pair is noted while it can be seen, and
/// kept between runs.
enum SessionAlias {
    private static let key = "sessionAliases"
    private static let limit = 400
    private static let lock = NSLock()
    private static var known: [String: String] = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]

    static func note(_ old: String, is current: String) {
        guard old != current, old != "no-session" else { return }
        lock.lock()
        defer { lock.unlock() }
        guard known[old] != current else { return }
        // Rarely full. When it is, start over: what is running now is noted again on the next scan.
        if known.count >= limit { known = [:] }
        known[old] = current
        UserDefaults.standard.set(known, forKey: key)
    }

    static func current(_ session: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return known[session] ?? session
    }
}

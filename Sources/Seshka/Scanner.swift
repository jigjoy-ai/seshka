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
    fileprivate var bundleRoot: String? {
        guard let marker = path.range(of: ".app/Contents/MacOS/") else { return nil }
        return String(path[..<marker.lowerBound]) + ".app/"
    }
}

struct SessionGroup: Identifiable {
    let id: String
    let project: String
    let title: String?
    var procs: [Proc]

    var shortID: String { String(id.prefix(8)) }
    var memory: UInt64 { procs.reduce(0) { $0 + $1.memory } }
    var oldest: Int { procs.map(\.age).max() ?? 0 }
}

enum Shell {
    static func run(_ path: String, _ args: [String], environment: [String: String] = [:]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        // Read before waiting, otherwise a full pipe blocks the child forever.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

enum Scanner {
    /// Marker variables Claude Code puts in the environment of everything it starts.
    private static let sessionPattern = #/\bCLAUDE_CODE_SESSION_ID=(\S+)/#
    private static let claudePidPattern = #/\bCLAUDE_PID=(\d+)/#

    /// Splits a line into `count` whitespace-separated fields; the last field keeps its inner spaces.
    fileprivate static func fields(_ line: Substring, _ count: Int) -> [String]? {
        var out: [String] = []
        var rest = line
        for _ in 0..<(count - 1) {
            rest = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard !rest.isEmpty else { return nil }
            let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? rest.endIndex
            out.append(String(rest[..<end]))
            rest = rest[end...]
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        guard !tail.isEmpty else { return nil }
        out.append(tail)
        return out
    }

    /// `[[dd-]hh:]mm:ss` as printed by `ps -o etime`.
    fileprivate static func seconds(fromElapsed etime: String) -> Int {
        var days = 0
        var rest = Substring(etime)
        if let dash = rest.firstIndex(of: "-") {
            days = Int(rest[..<dash]) ?? 0
            rest = rest[rest.index(after: dash)...]
        }
        var parts = rest.split(separator: ":").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.insert(0, at: 0) }
        return days * 86400 + parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    static func scan() -> [Proc] {
        let uid = String(getuid())
        let me = getpid()

        var comm: [Int32: String] = [:]
        var paths: [Int32: String] = [:]
        var parent: [Int32: Int32] = [:]
        for line in Shell.run("/bin/ps", ["-A", "-o", "pid=,ppid=,comm="]).split(separator: "\n") {
            guard let f = fields(line, 3), let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            comm[pid] = (f[2] as NSString).lastPathComponent
            paths[pid] = f[2]
            parent[pid] = ppid
        }

        var commands: [Int32: String] = [:]
        var ages: [Int32: Int] = [:]
        for line in Shell.run("/bin/ps", ["ww", "-U", uid, "-o", "pid=,etime=,command="]).split(separator: "\n") {
            guard let f = fields(line, 3), let pid = Int32(f[0]) else { continue }
            ages[pid] = seconds(fromElapsed: f[1])
            commands[pid] = f[2]
        }

        func isClaude(_ pid: Int32) -> Bool { comm[pid] == "claude" }

        func hasClaudeAncestor(_ start: Int32) -> Bool {
            var pid = start
            var seen = Set<Int32>()
            while pid > 1, let next = parent[pid], !seen.contains(pid) {
                seen.insert(pid)
                pid = next
                if isClaude(pid) { return true }
            }
            return false
        }

        var procs: [Proc] = []
        // The "e" flag appends each process's environment to its command line.
        // macOS only allows that for the current user's own processes.
        let withEnv = Shell.run("/bin/ps", ["eww", "-U", uid, "-o", "pid=,ppid=,etime=,command="])
        for line in withEnv.split(separator: "\n") where line.contains("CLAUDECODE=1") {
            guard let f = fields(line, 4), let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            if pid == me || ppid == me || isClaude(pid) { continue }
            // Look for the markers only in the environment, not in the command's own
            // arguments (e.g. a `grep CLAUDECODE=1` would otherwise match itself).
            var env = f[3]
            if let command = commands[pid], env.hasPrefix(command) {
                env = String(env.dropFirst(command.count))
            }
            guard env.contains("CLAUDECODE=1") else { continue }
            let session = env.firstMatch(of: sessionPattern).map { String($0.1) } ?? "no-session"
            let claudePid = env.firstMatch(of: claudePidPattern).flatMap { Int32($0.1) }
            let alive = (claudePid.map(isClaude) ?? false) || hasClaudeAncestor(pid)
            procs.append(Proc(
                pid: pid,
                ppid: ppid,
                age: seconds(fromElapsed: f[2]),
                sessionID: session,
                sessionAlive: alive,
                command: commands[pid] ?? "?",
                path: paths[pid] ?? ""
            ))
        }
        guard !procs.isEmpty else { return [] }

        // Some apps keep their environment unreadable (Chrome does), so the marker cannot be seen on them.
        // A process started by a marked one still belongs to that session, with or without a marker.
        var marked: [Int32: Int] = [:]
        for (i, p) in procs.enumerated() { marked[p.pid] = i }
        for (pid, command) in commands where marked[pid] == nil && pid != me && !isClaude(pid) {
            var owner: Int?
            var at = pid
            var seen = Set<Int32>()
            while at > 1, let up = parent[at], seen.insert(at).inserted {
                // Past seshka or another Claude Code process it is no longer this session's doing.
                if up == me || isClaude(up) { break }
                if let hit = marked[up] { owner = hit; break }
                at = up
            }
            guard let owner else { continue }
            procs.append(Proc(
                pid: pid,
                ppid: parent[pid] ?? 0,
                age: ages[pid] ?? 0,
                sessionID: procs[owner].sessionID,
                sessionAlive: procs[owner].sessionAlive,
                command: command,
                path: paths[pid] ?? ""
            ))
        }

        // An app's helper processes (a browser has one per tab) are part of the app: one row, not twenty.
        var index: [Int32: Int] = [:]
        for (i, p) in procs.enumerated() { index[p.pid] = i }
        var folded = Set<Int>()
        for i in procs.indices {
            var app: Int?
            var at = i
            var seen = Set<Int>()
            while seen.insert(at).inserted, let up = index[procs[at].ppid],
                  let root = procs[up].bundleRoot, procs[i].path.hasPrefix(root) {
                app = up
                at = up
            }
            guard let app else { continue }
            procs[app].helpers.append(Proc.Helper(pid: procs[i].pid, command: procs[i].command))
            folded.insert(i)
        }
        procs = procs.indices.filter { !folded.contains($0) }.map { procs[$0] }

        index = [:]
        for (i, p) in procs.enumerated() {
            index[p.pid] = i
            procs[i].memory = Footprint.bytes(of: p.pid)
            for helper in p.helpers {
                index[helper.pid] = i
                procs[i].memory += Footprint.bytes(of: helper.pid)
            }
        }
        let pidList = procs.flatMap { [$0.pid] + $0.helpers.map(\.pid) }.map(String.init).joined(separator: ",")

        var current: Int?
        let mains = procs.map { String($0.pid) }.joined(separator: ",")
        for line in Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", mains, "-Fpn"]).split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst()).flatMap { index[$0] }
            } else if line.hasPrefix("n"), let i = current {
                procs[i].cwd = String(line.dropFirst())
            }
        }

        current = nil
        let listening = Shell.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pidList, "-Fpn"])
        for line in listening.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = Int32(line.dropFirst()).flatMap { index[$0] }
            } else if line.hasPrefix("n"), let i = current,
                      let port = line.split(separator: ":").last.map(String.init),
                      !procs[i].ports.contains(port) {
                procs[i].ports.append(port)
            }
        }
        return procs
    }

    static func group(_ procs: [Proc]) -> [SessionGroup] {
        var bySession: [String: [Proc]] = [:]
        for p in procs { bySession[p.sessionID, default: []].append(p) }
        return bySession
            .map { sid, members in
                let info = SessionInfo.lookup(sid)
                return SessionGroup(
                    id: sid,
                    project: info.project,
                    title: info.title,
                    procs: members.sorted { $0.age > $1.age }
                )
            }
            .sorted { $0.oldest > $1.oldest }
    }
}

/// Project name and title of a session, read from Claude Code's own session files.
enum SessionInfo {
    private static var cache: [String: (project: String, title: String?)] = [:]
    private static let lock = NSLock()

    static func lookup(_ sid: String) -> (project: String, title: String?) {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[sid] { return hit }
        let result = read(sid)
        // A missing file may appear later for a brand-new session, so only cache real hits.
        if result.project != unknownProject { cache[sid] = result }
        return result
    }

    static let unknownProject = "unknown project"

    private static func read(_ sid: String) -> (project: String, title: String?) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let root = home + "/.claude/projects"
        guard let dirs = try? fm.contentsOfDirectory(atPath: root) else { return (unknownProject, nil) }
        // Claude Code names each project folder after its path, with every
        // non-alphanumeric character replaced by "-".
        let prefix = String(home.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        for dir in dirs {
            let file = "\(root)/\(dir)/\(sid).jsonl"
            guard fm.fileExists(atPath: file) else { continue }
            var name = dir
            if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            return (name.isEmpty ? "~" : name, title(inFile: file))
        }
        return (unknownProject, nil)
    }

    /// Session files can be hundreds of megabytes, so only the tail is read.
    private static func title(inFile path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk: UInt64 = 2 * 1024 * 1024
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n").reversed() where line.contains("\"ai-title\"") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let title = json["aiTitle"] as? String, !title.isEmpty else { continue }
            return title
        }
        return nil
    }
}

enum Footprint {
    /// Physical memory footprint of a process in bytes, or 0 if it cannot be read.
    /// Unlike the RSS column of `ps`, this counts compressed and VM-backed memory,
    /// which is most of what an emulator or a virtual machine uses.
    static func bytes(of pid: Int32) -> UInt64 {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : 0
    }
}

enum Killer {
    static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// PIDs get reused, so make sure the PID still belongs to the process the user saw.
    static func stillSame(_ proc: Proc) -> Bool {
        stillRuns(proc.pid, as: proc.command)
    }

    private static func stillRuns(_ pid: Int32, as command: String) -> Bool {
        let now = Shell.run("/bin/ps", ["ww", "-p", String(pid), "-o", "command="])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !now.isEmpty && now == command
    }

    /// Asks each process to exit, then force-kills whatever ignored the request.
    /// Returns the PIDs that needed the force-kill.
    @discardableResult
    static func terminate(_ procs: [Proc], grace: TimeInterval = 2.0) -> [Int32] {
        let same = procs.filter(stillSame)
        defer { sweepHelpers(of: same) }
        let targets = same.map(\.pid)
        for pid in targets { kill(pid, SIGTERM) }

        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, targets.contains(where: isRunning) {
            Thread.sleep(forTimeInterval: 0.1)
        }

        let stubborn = targets.filter(isRunning)
        for pid in stubborn { kill(pid, SIGKILL) }
        // Give the system a moment to actually remove them before the next scan.
        let reaped = Date().addingTimeInterval(1.0)
        while Date() < reaped, stubborn.contains(where: isRunning) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        return stubborn
    }

    /// An app's helpers exit on their own once the app is gone. Any that did not are forced out.
    private static func sweepHelpers(of procs: [Proc]) {
        let helpers = procs.filter { !isRunning($0.pid) }.flatMap(\.helpers)
        guard !helpers.isEmpty else { return }
        let settled = Date().addingTimeInterval(1.0)
        while Date() < settled, helpers.contains(where: { isRunning($0.pid) }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
        for helper in helpers where isRunning(helper.pid) && stillRuns(helper.pid, as: helper.command) {
            kill(helper.pid, SIGKILL)
        }
    }
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

extension Scanner {
    /// Every open Claude Code session, with the background processes from `procs` that belong to it.
    ///
    /// Claude Code keeps a small record per running process in ~/.claude/sessions/<pid>.json, with the
    /// session's ID and whether it is busy or idle. That file is not a documented interface, so every
    /// field is optional here: without it a session still shows, just without a status.
    static func sessions(procs: [Proc]) -> [RunningSession] {
        let uid = String(getuid())
        var claude: [(pid: Int32, ppid: Int32, age: Int)] = []
        for line in Shell.run("/bin/ps", ["-U", uid, "-o", "pid=,ppid=,etime=,comm="]).split(separator: "\n") {
            guard let f = fields(line, 4), let pid = Int32(f[0]), let ppid = Int32(f[1]),
                  (f[3] as NSString).lastPathComponent == "claude" else { continue }
            claude.append((pid, ppid, seconds(fromElapsed: f[2])))
        }
        // A claude process started by another one is part of that session, not a session of its own.
        let pids = Set(claude.map(\.pid))
        claude.removeAll { pids.contains($0.ppid) }
        guard !claude.isEmpty else { return [] }

        let list = claude.map { String($0.pid) }.joined(separator: ",")
        var commands: [Int32: String] = [:]
        for line in Shell.run("/bin/ps", ["ww", "-p", list, "-o", "pid=,command="]).split(separator: "\n") {
            guard let f = fields(line, 2), let pid = Int32(f[0]) else { continue }
            commands[pid] = f[1]
        }
        // Claude Code records each process's start time in UTC and in English, so ask ps for the same.
        var started: [Int32: String] = [:]
        let utc = ["TZ": "UTC", "LC_ALL": "C"]
        for line in Shell.run("/bin/ps", ["-p", list, "-o", "pid=,lstart="], environment: utc).split(separator: "\n") {
            guard let f = fields(line, 2), let pid = Int32(f[0]) else { continue }
            started[pid] = squeeze(f[1])
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return claude.map { entry in
            var record: [String: Any] = [:]
            if let data = FileManager.default.contents(atPath: "\(home)/.claude/sessions/\(entry.pid).json"),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               // PIDs get reused: the record must be about the process that is running now.
               let recorded = json["procStart"] as? String, squeeze(recorded) == started[entry.pid] {
                record = json
            }
            let sessionID = record["sessionId"] as? String
            let cwd = record["cwd"] as? String ?? ""
            let info = sessionID.map(SessionInfo.lookup)
            let project: String
            if let info, info.project != SessionInfo.unknownProject {
                project = info.project
            } else {
                project = cwd.isEmpty ? "Claude Code" : (cwd as NSString).lastPathComponent
            }

            let status: RunningSession.Status
            switch record["status"] as? String {
            case "busy": status = .busy
            case "idle": status = .idle
            case let other?: status = .other(other)
            case nil: status = .unknown
            }
            let since = milliseconds(record["statusUpdatedAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }

            var process = Proc(pid: entry.pid, ppid: entry.ppid, age: entry.age, sessionID: sessionID ?? "no-session",
                               sessionAlive: true, command: commands[entry.pid] ?? "claude")
            process.cwd = cwd
            process.memory = Footprint.bytes(of: entry.pid)
            return RunningSession(
                process: process,
                sessionID: sessionID,
                project: project,
                title: info?.title,
                status: status,
                statusSince: since,
                procs: procs.filter { $0.sessionAlive && $0.age >= 60 && $0.sessionID == sessionID }
            )
        }
    }

    private static func squeeze(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ")
    }

    private static func milliseconds(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

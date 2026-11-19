import Foundation

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
        let records = records(of: claude.map(\.pid))

        return claude.map { entry in
            let record = records[entry.pid] ?? [:]
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

    /// Claude Code's own record of each of these processes, for the ones that have one.
    static func records(of pids: [Int32]) -> [Int32: [String: Any]] {
        guard !pids.isEmpty else { return [:] }
        // Claude Code records each process's start time in UTC and in English, so ask ps for the same.
        var started: [Int32: String] = [:]
        let utc = ["TZ": "UTC", "LC_ALL": "C"]
        let list = pids.map(String.init).joined(separator: ",")
        for line in Shell.run("/bin/ps", ["-p", list, "-o", "pid=,lstart="], environment: utc).split(separator: "\n") {
            guard let f = fields(line, 2), let pid = Int32(f[0]) else { continue }
            started[pid] = squeeze(f[1])
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var records: [Int32: [String: Any]] = [:]
        for pid in pids {
            guard let data = FileManager.default.contents(atPath: "\(home)/.claude/sessions/\(pid).json"),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  // PIDs get reused: the record must be about the process that is running now.
                  let recorded = json["procStart"] as? String, squeeze(recorded) == started[pid] else { continue }
            records[pid] = json
        }
        return records
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

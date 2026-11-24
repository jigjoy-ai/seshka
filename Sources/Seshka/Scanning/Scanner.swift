import Foundation

enum Scanner {
    /// Marker variables Claude Code puts in the environment of everything it starts.
    private static let sessionPattern = #/\bCLAUDE_CODE_SESSION_ID=(\S+)/#
    private static let claudePidPattern = #/\bCLAUDE_PID=(\d+)/#

    /// Splits a line into `count` whitespace-separated fields; the last field keeps its inner spaces.
    static func fields(_ line: Substring, _ count: Int) -> [String]? {
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
    static func seconds(fromElapsed etime: String) -> Int {
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
        var groups: [Int32: Int32] = [:]
        for line in Shell.run("/bin/ps", ["-A", "-o", "pid=,ppid=,pgid=,comm="]).split(separator: "\n") {
            guard let f = fields(line, 4), let pid = Int32(f[0]), let ppid = Int32(f[1]), let pgid = Int32(f[2]) else { continue }
            comm[pid] = (f[3] as NSString).lastPathComponent
            paths[pid] = f[3]
            parent[pid] = ppid
            groups[pid] = pgid
        }

        var commands: [Int32: String] = [:]
        var ages: [Int32: Int] = [:]
        for line in Shell.run("/bin/ps", ["ww", "-U", uid, "-o", "pid=,etime=,command="]).split(separator: "\n") {
            guard let f = fields(line, 3), let pid = Int32(f[0]) else { continue }
            ages[pid] = seconds(fromElapsed: f[1])
            commands[pid] = f[2]
        }

        func isClaude(_ pid: Int32) -> Bool { comm[pid] == "claude" }

        /// The nearest Claude Code process above this one, if its line of parents reaches one.
        func claudeAncestor(_ start: Int32) -> Int32? {
            var pid = start
            var seen = Set<Int32>()
            while pid > 1, let next = parent[pid], !seen.contains(pid) {
                seen.insert(pid)
                pid = next
                if isClaude(pid) { return pid }
            }
            return nil
        }

        func hasClaudeAncestor(_ start: Int32) -> Bool { claudeAncestor(start) != nil }

        /// The session a process belongs to, and whether that session is still open.
        struct Owner {
            let session: String
            let alive: Bool
        }
        var owners: [Int32: Owner] = [:]
        /// In the order found: the marked ones first, as before.
        var found: [Int32] = []
        var marked = Set<Int32>()
        /// The Claude Code process a marked process names as its own, when it names one.
        var named: [Int32: Int32] = [:]
        /// Processes that show no environment at all. macOS hides it for its own programs (/bin/bash,
        /// /usr/bin/ssh, /usr/bin/tail) and for some apps, Chrome among them.
        var unreadable = Set<Int32>()

        // The "e" flag appends each process's environment to its command line.
        // macOS only allows that for the current user's own processes.
        let withEnv = Shell.run("/bin/ps", ["eww", "-U", uid, "-o", "pid=,ppid=,etime=,command="])
        for line in withEnv.split(separator: "\n") {
            guard let f = fields(line, 4), let pid = Int32(f[0]), let ppid = Int32(f[1]) else { continue }
            // Look for the markers only in the environment, not in the command's own
            // arguments (e.g. a `grep CLAUDECODE=1` would otherwise match itself).
            var env = f[3]
            if let command = commands[pid], env.hasPrefix(command) {
                env = String(env.dropFirst(command.count))
                if env.allSatisfy({ $0 == " " }) { unreadable.insert(pid) }
            }
            if pid == me || ppid == me || isClaude(pid) { continue }
            guard env.contains("CLAUDECODE=1") else { continue }
            let session = env.firstMatch(of: sessionPattern).map { String($0.1) } ?? "no-session"
            let claudePid = env.firstMatch(of: claudePidPattern).flatMap { Int32($0.1) }
            let alive = (claudePid.map(isClaude) ?? false) || hasClaudeAncestor(pid)
            owners[pid] = Owner(session: session, alive: alive)
            if let claudePid, isClaude(claudePid) { named[pid] = claudePid }
            marked.insert(pid)
            found.append(pid)
        }

        // The marker is not the only trace. Three more, for the processes it cannot be read on:
        //
        //   1. Claude Code sends each command's output to a file of its own, in a folder named after the
        //      session. A process still writing there says which session started it, whoever its parent is now.
        //   2. A process started by one that is already placed belongs to the same session, and so does one
        //      whose line of parents ends at an open Claude Code process.
        //   3. The marker is handed down from parent to child. So a parent that hides its environment had
        //      it too, if its child shows it: the script that keeps restarting a server belongs with the server.
        //   4. Claude Code starts every command in a process group of its own, which whatever the command
        //      starts stays in. CommandWatch notes each such group as it is started, and a process found in
        //      one later belongs to that command's session, even with no parent, marker or output left.
        //
        // Merely sharing a process group with something already placed is deliberately not one of them. A
        // tool that runs Claude Code itself (an editor, an orchestrator) shares its group with it, and
        // would be taken for a leftover.
        let claudes = commands.keys.filter(isClaude)
        var sessionOf = records(of: claudes).compactMapValues { $0["sessionId"] as? String }
        // A Claude Code process started by another one works for that one's session.
        for pid in claudes where sessionOf[pid] == nil {
            var at = pid
            var seen = Set<Int32>()
            while let up = parent[at], up > 1, seen.insert(at).inserted {
                if isClaude(up), let session = sessionOf[up] {
                    sessionOf[pid] = session
                    break
                }
                at = up
            }
        }
        let open = Set(sessionOf.values)
        let candidates = commands.keys.filter { $0 != me && parent[$0] != me && !isClaude($0) }.sorted()
        CommandWatch.shared.settle(groups: groups, ages: ages)
        CommandWatch.shared.watch(sessionOf)

        for pid in candidates where owners[pid] == nil {
            guard let session = Output.session(of: pid) else { continue }
            owners[pid] = Owner(session: session, alive: hasClaudeAncestor(pid) || open.contains(session))
            found.append(pid)
        }
        // Only what cannot show a marker is placed by its group: a process that shows an environment
        // without one was started that way on purpose.
        for pid in candidates where owners[pid] == nil && unreadable.contains(pid) {
            guard let group = groups[pid], let command = CommandWatch.shared.command(ofGroup: group) else { continue }
            owners[pid] = Owner(session: command.session, alive: isClaude(command.claude) || hasClaudeAncestor(pid))
            found.append(pid)
        }

        var changed = true
        var rounds = 0
        while changed, rounds < 5 {
            changed = false
            rounds += 1
            // Upwards: the parents that hide their environment, as far as they go. Never Claude Code itself,
            // never launchd, which adopts whatever lost its parent, and never past a parent that shows an
            // environment without the marker.
            for pid in found {
                guard let owner = owners[pid] else { continue }
                var at = pid
                while let up = parent[at], up > 1, up != me, !isClaude(up), owners[up] == nil,
                      unreadable.contains(up), commands[up] != nil {
                    owners[up] = owner
                    found.append(up)
                    changed = true
                    at = up
                }
            }
            for pid in candidates where owners[pid] == nil {
                var owner: Owner?
                var at = pid
                var seen = Set<Int32>()
                while at > 1, let up = parent[at], seen.insert(at).inserted {
                    // Past seshka it is no longer a session's doing.
                    if up == me { break }
                    if isClaude(up) {
                        // Only what cannot show a marker is taken on trust, and never Claude Code's own helpers.
                        if unreadable.contains(pid), groups[pid] != groups[up], let session = sessionOf[up] {
                            owner = Owner(session: session, alive: true)
                        }
                        break
                    }
                    if let hit = owners[up] { owner = hit; break }
                    at = up
                }
                guard let owner else { continue }
                owners[pid] = owner
                found.append(pid)
                changed = true
            }
        }
        guard !found.isEmpty else { return [] }

        // The session a process names is the one it was started in. Claude Code moves on to a new session
        // (after /clear, or when a long conversation is carried over into a new one) without restarting
        // what it has running, an MCP server for one. So what still hangs off an open Claude Code process
        // belongs to the session that process has now, whatever it was called when it started.
        for pid in found {
            guard let claude = claudeAncestor(pid) ?? named[pid], let session = sessionOf[claude] else {
                // Its session is closed. If it moved on before closing, the ID it ended with is the one
                // its conversation is filed under.
                if let owner = owners[pid], !owner.alive {
                    owners[pid] = Owner(session: SessionAlias.current(owner.session), alive: false)
                }
                continue
            }
            if let was = owners[pid]?.session { SessionAlias.note(was, is: session) }
            owners[pid] = Owner(session: session, alive: true)
        }

        var procs: [Proc] = found.map { pid in
            Proc(
                pid: pid,
                ppid: parent[pid] ?? 0,
                age: ages[pid] ?? 0,
                sessionID: owners[pid]?.session ?? "no-session",
                sessionAlive: owners[pid]?.alive ?? false,
                command: commands[pid] ?? "?",
                path: paths[pid] ?? "",
                group: groups[pid] ?? 0
            )
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

        // Claude Code runs each command inside a shell of its own. Next to what the command started, that
        // shell is only wrapping: it goes into the first row of its group and is killed with it. Alone, it
        // is the command (a loop typed straight into it, say) and gets a row, showing what it runs.
        folded = []
        for i in procs.indices where !marked.contains(procs[i].pid) {
            guard let inner = unwrap(procs[i]) else { continue }
            let host = procs.indices.first {
                // Of the same session: a group can hold what another session started, and killing that
                // must not take this session's shell with it.
                $0 != i && !folded.contains($0) && procs[$0].group == procs[i].group && unwrap(procs[$0]) == nil
                    && procs[$0].sessionID == procs[i].sessionID && procs[$0].sessionAlive == procs[i].sessionAlive
            }
            if let host {
                procs[host].helpers.append(Proc.Helper(pid: procs[i].pid, command: procs[i].command))
                folded.insert(i)
            } else {
                procs[i].wrapped = inner
            }
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
        for i in procs.indices {
            procs[i].worktree = Worktree.containing(procs[i].cwd)
        }
        return procs
    }

    /// The command inside the shell Claude Code wraps it in, or nil for any other process.
    /// The wrapping is `zsh -c -l <setup> && eval '<command>' < /dev/null && pwd -P >| <file>`.
    private static func unwrap(_ proc: Proc) -> String? {
        guard proc.pid == proc.group, ["zsh", "bash", "sh"].contains(proc.executable),
              let start = proc.command.range(of: " eval '") else { return nil }
        var inner = proc.command[start.upperBound...]
        if let end = inner.range(of: "' < /dev/null", options: .backwards) ?? inner.range(of: "'", options: .backwards) {
            inner = inner[..<end.lowerBound]
        }
        // A quote inside the command is written as '"'"'.
        let text = inner.replacingOccurrences(of: "'\"'\"'", with: "'").replacingOccurrences(of: "\\012", with: " ")
        return text.isEmpty ? nil : text
    }

    /// One group for each session and each worktree it worked in. A session's groups stay together.
    static func group(_ procs: [Proc]) -> [SessionGroup] {
        var buckets: [String: [Proc]] = [:]
        var oldest: [String: Int] = [:]
        for p in procs {
            buckets[p.sessionID + "\n" + (p.worktree?.root ?? ""), default: []].append(p)
            oldest[p.sessionID] = max(oldest[p.sessionID] ?? 0, p.age)
        }
        return buckets
            .map { key, members in
                let info = SessionInfo.lookup(members[0].sessionID)
                return SessionGroup(
                    id: key,
                    sessionID: members[0].sessionID,
                    project: info.project,
                    title: info.title,
                    worktree: members[0].worktree,
                    procs: members.sorted { $0.age > $1.age }
                )
            }
            .sorted {
                let a = oldest[$0.sessionID] ?? 0, b = oldest[$1.sessionID] ?? 0
                if a != b { return a > b }
                if $0.sessionID != $1.sessionID { return $0.sessionID < $1.sessionID }
                // The main folder first, then the worktrees by name.
                return ($0.worktree?.name ?? "") < ($1.worktree?.name ?? "")
            }
    }
}

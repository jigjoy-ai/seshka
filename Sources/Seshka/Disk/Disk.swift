import Foundation

enum Disk {
    /// What is in use right now. Nothing a session or a process still needs is ever offered.
    struct Context {
        /// Folders that open sessions and their processes, leftover ones included, run in.
        var folders: [String] = []
        /// Sessions that are open, or that still have something running.
        var sessions: Set<String> = []
        /// Project folders (as Claude Code names them) of open sessions whose ID could not be read.
        var projects: Set<String> = []

        func uses(_ path: String) -> Bool {
            folders.contains { $0 == path || $0.hasPrefix(path + "/") }
        }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Reads what is running, for a decision about what may be removed.
    static func context() -> Context {
        let procs = Scanner.scan()
        let sessions = Scanner.sessions(procs: procs)
        var context = Context()
        context.folders = (procs.map(\.cwd) + sessions.map(\.process.cwd)).filter { !$0.isEmpty }
        context.sessions = Set(procs.map(\.sessionID) + sessions.compactMap(\.sessionID))
        // A session with no record keeps its ID to itself. Its whole project is left alone instead.
        let unread = sessions.filter { $0.sessionID == nil }.map { String($0.process.pid) }
        if !unread.isEmpty {
            for line in Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", unread.joined(separator: ","), "-Fn"]).split(separator: "\n")
            where line.hasPrefix("n") {
                context.folders.append(String(line.dropFirst()))
                context.projects.insert(SessionInfo.folderName(ofPath: String(line.dropFirst())))
            }
        }
        return context
    }

    // MARK: - Worktrees

    /// The worktrees Claude Code made (it keeps them in <repository>/.claude/worktrees), in every
    /// repository a session has worked in. Not measured yet.
    static func worktrees(_ context: Context) -> [DiskItem] {
        let fm = FileManager.default
        var found: [(path: String, repository: String)] = []
        for repository in repositories(extra: context.folders) {
            let folder = repository + "/.claude/worktrees"
            guard let names = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = folder + "/" + name
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
                found.append((path, repository))
            }
        }
        // Each one asks git whether anything in it is uncommitted, which takes a second or so in a big
        // repository. All at once, so the list does not wait on the sum of them.
        var items = [DiskItem?](repeating: nil, count: found.count)
        let filling = NSLock()
        DispatchQueue.concurrentPerform(iterations: found.count) { i in
            let item = worktree(at: found[i].path, repository: found[i].repository, context)
            filling.lock()
            items[i] = item
            filling.unlock()
        }
        return items.compactMap { $0 }
    }

    private static func worktree(at path: String, repository: String, _ context: Context) -> DiskItem {
        let name = (path as NSString).lastPathComponent
        let known = Worktree.read(root: path)
        var state = DiskItem.State.removable
        if context.uses(path) {
            state = .busy("A session or a process is running in it")
        } else if let reason = lock(of: known) {
            state = .busy(reason)
        } else if known == nil || Git.path == nil {
            // Not a worktree git knows, or no git to ask: there is no telling what is in it.
            state = .uncommitted
        } else if let git = Git.path,
                  !Shell.run(git, ["--no-optional-locks", "-C", path, "status", "--porcelain"]).isEmpty {
            state = .uncommitted
        }

        var parts = [(repository as NSString).lastPathComponent]
        if let branch = known?.branch, branch != name, branch != "worktree-" + name { parts.append(branch) }
        if let touched = lastTouched(path, records: known?.records) {
            parts.append("untouched for \(humanAge(max(0, Int(Date().timeIntervalSince(touched)))))")
        }
        return DiskItem(id: path, kind: .worktree, title: name, detail: parts.joined(separator: "  ·  "),
                        paths: [path], state: state, repository: repository)
    }

    /// Why a locked worktree may not be removed, or nil when it is not locked or the lock is stale.
    /// Claude Code locks a worktree while an agent works in it, and names its own process in the lock.
    private static func lock(of worktree: Worktree?) -> String? {
        guard let records = worktree?.records,
              let reason = try? String(contentsOfFile: records + "/locked", encoding: .utf8) else { return nil }
        guard let match = reason.firstMatch(of: #/\(pid (\d+)/#), let pid = Int32(match.1) else {
            return "Locked in git"
        }
        let name = Shell.run("/bin/ps", ["-p", String(pid), "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name as NSString).lastPathComponent == "claude" ? "An agent is working in it" : nil
    }

    private static func lastTouched(_ path: String, records: String?) -> Date? {
        let fm = FileManager.default
        var files = [path]
        if let records { files += [records + "/HEAD", records + "/index"] }
        return files.compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
    }

    /// The folder each project folder of Claude Code stands for, once read.
    private static var folderOfProject: [String: String] = [:]
    private static let reading = NSLock()

    /// The main folder of every repository a session has worked in.
    private static func repositories(extra: [String]) -> [String] {
        let fm = FileManager.default
        let root = home + "/.claude/projects"
        var folders = Set(extra)
        for project in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            reading.lock()
            let known = folderOfProject[project]
            reading.unlock()
            if let known {
                folders.insert(known)
                continue
            }
            // The folder's name cannot be turned back into a path, but every line of a session's file
            // says where it ran.
            guard let file = (try? fm.contentsOfDirectory(atPath: root + "/" + project))?.first(where: { $0.hasSuffix(".jsonl") }),
                  let handle = FileHandle(forReadingAtPath: "\(root)/\(project)/\(file)") else { continue }
            let head = String(decoding: (try? handle.read(upToCount: 256 * 1024)) ?? Data(), as: UTF8.self)
            try? handle.close()
            guard let match = head.firstMatch(of: #/"cwd":("(?:[^"\\]|\\.)*")/#),
                  let folder = try? JSONDecoder().decode(String.self, from: Data(match.1.utf8)) else { continue }
            reading.lock()
            folderOfProject[project] = folder
            reading.unlock()
            folders.insert(folder)
        }

        var repositories = Set<String>()
        for folder in folders {
            var at = folder
            while at.count > 1 {
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: at + "/.git", isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        repositories.insert(at)
                    } else if let main = Worktree.read(root: at)?.repository {
                        repositories.insert(main)
                    }
                    break
                }
                at = (at as NSString).deletingLastPathComponent
            }
        }
        return repositories.sorted()
    }

    // MARK: - Scratch files

    /// Where Claude Code keeps each session's scratch files and command output: one folder per project,
    /// and in it one per session.
    private static let scratchRoot = "/private/tmp/claude-\(getuid())"
    private static let sessionFolder = #/^[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$/#

    /// The scratch folders of closed sessions, measured: one item for each project with a lot in them,
    /// and one for all the rest.
    static func scratch(_ context: Context) -> [DiskItem] {
        let fm = FileManager.default
        var folders: [(project: String, path: String)] = []
        for project in (try? fm.contentsOfDirectory(atPath: scratchRoot)) ?? [] where !context.projects.contains(project) {
            for session in (try? fm.contentsOfDirectory(atPath: scratchRoot + "/" + project)) ?? []
            where session.wholeMatch(of: sessionFolder) != nil && isClosed(session, in: project, context) {
                folders.append((project, "\(scratchRoot)/\(project)/\(session)"))
            }
        }
        let sizes = measure(folders.map(\.path))

        var byProject: [String: (paths: [String], bytes: UInt64)] = [:]
        for folder in folders {
            byProject[folder.project, default: ([], 0)].paths.append(folder.path)
            byProject[folder.project]?.bytes += sizes[folder.path] ?? 0
        }
        var items: [DiskItem] = []
        var rest: (paths: [String], bytes: UInt64, projects: Int) = ([], 0, 0)
        for (project, found) in byProject {
            guard found.bytes >= 20 * 1_048_576 else {
                rest.paths += found.paths
                rest.bytes += found.bytes
                rest.projects += 1
                continue
            }
            let count = found.paths.count
            items.append(DiskItem(id: "scratch:" + project, kind: .scratch, title: SessionInfo.projectName(ofFolder: project),
                                  detail: "\(count) closed session\(count == 1 ? "" : "s")",
                                  paths: found.paths, state: .removable, bytes: found.bytes))
        }
        items.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        if rest.bytes > 0 {
            let count = rest.paths.count
            items.append(DiskItem(id: "scratch:rest", kind: .scratch,
                                  title: items.isEmpty ? "All projects" : "\(rest.projects) other project\(rest.projects == 1 ? "" : "s")",
                                  detail: "\(count) closed session\(count == 1 ? "" : "s")",
                                  paths: rest.paths, state: .removable, bytes: rest.bytes))
        }
        return items
    }

    /// A session's scratch folder may go once the session is closed, has nothing running, and has not
    /// been written to for an hour.
    private static func isClosed(_ session: String, in project: String, _ context: Context) -> Bool {
        guard !context.sessions.contains(session), !context.projects.contains(project) else { return false }
        let folder = "\(scratchRoot)/\(project)/\(session)"
        let fm = FileManager.default
        let touched = [folder, folder + "/tasks", folder + "/scratchpad"]
            .compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
        return touched.map { Date().timeIntervalSince($0) > 3600 } ?? false
    }

    // MARK: - Caches

    private struct Cache {
        let name: String
        let paths: [String]
        let note: String
    }

    /// Caches that developer tools fill again by themselves, the next time they need what was in them.
    /// Every path is under the home folder. What has to be installed again by hand does not belong here:
    /// without the browsers Playwright and Puppeteer download, their tests fail until someone reinstalls them.
    private static let caches = [
        Cache(name: "Gradle caches", paths: [".gradle/caches"], note: "Gradle downloads its dependencies again on the next build."),
        Cache(name: "pnpm store", paths: ["Library/pnpm/store", "Library/Caches/pnpm", ".local/share/pnpm/store"],
              note: "Projects keep working. pnpm downloads packages again on the next install."),
        Cache(name: "Yarn cache", paths: [".yarn/berry/cache", "Library/Caches/Yarn"], note: "Yarn downloads packages again on the next install."),
        Cache(name: "npm cache", paths: [".npm/_cacache"], note: "npm downloads packages again on the next install."),
        Cache(name: "Bun cache", paths: [".bun/install/cache"], note: "Bun downloads packages again on the next install."),
        Cache(name: "Xcode DerivedData", paths: ["Library/Developer/Xcode/DerivedData"], note: "Xcode builds every project from scratch the next time."),
        Cache(name: "CocoaPods cache", paths: ["Library/Caches/CocoaPods"], note: "CocoaPods downloads pods again on the next install."),
        Cache(name: "Homebrew downloads", paths: ["Library/Caches/Homebrew"], note: "Installed packages stay. Only the downloaded installers go."),
        Cache(name: "pip cache", paths: ["Library/Caches/pip"], note: "pip downloads packages again on the next install."),
        Cache(name: "uv cache", paths: [".cache/uv"], note: "uv downloads packages again on the next install."),
        Cache(name: "Cargo registry", paths: [".cargo/registry"], note: "Cargo downloads crates again on the next build."),
        Cache(name: "Go build cache", paths: ["Library/Caches/go-build"], note: "Go compiles everything again on the next build."),
        Cache(name: "Electron downloads", paths: ["Library/Caches/electron"], note: "Electron is downloaded again when a project installs it."),
    ]

    /// Smaller than this, a cache is not worth a row.
    static let smallestCache: UInt64 = 100 * 1_048_576

    /// The caches found on this Mac. Not measured yet.
    static func cachesFound() -> [DiskItem] {
        caches.compactMap { cache in
            let found = cache.paths.map { home + "/" + $0 }.filter { FileManager.default.fileExists(atPath: $0) }
            guard !found.isEmpty else { return nil }
            return DiskItem(id: "cache:" + cache.name, kind: .cache, title: cache.name,
                            detail: found.map(abbreviate).joined(separator: ", "), paths: found, state: .removable, note: cache.note)
        }
    }

    // MARK: - Measuring and removing

    /// How much disk each path takes, in bytes.
    static func measure(_ paths: [String]) -> [String: UInt64] {
        var sizes: [String: UInt64] = [:]
        // Few enough at a time to fit on one command line.
        for start in stride(from: 0, to: paths.count, by: 200) {
            let batch = Array(paths[start..<min(start + 200, paths.count)])
            for line in Shell.run("/usr/bin/du", ["-sk"] + batch).split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t"), let kilobytes = UInt64(line[..<tab].trimmingCharacters(in: .whitespaces)) else { continue }
                sizes[String(line[line.index(after: tab)...])] = kilobytes * 1024
            }
        }
        return sizes
    }

    /// How much disk removing these paths would give back.
    static func size(of paths: [String]) -> UInt64 {
        FolderSize.measure(paths)
    }

    /// Removes an item, after checking once more that nothing uses it. Returns what went wrong, or nil.
    static func remove(_ item: DiskItem, _ context: Context) -> String? {
        let fm = FileManager.default
        switch item.kind {
        case .cache:
            return delete(item.paths)
        case .scratch:
            // Only what is still closed. A session reopened since the list was made keeps its folder.
            let closed = item.paths.filter { path in
                let parts = path.split(separator: "/").map(String.init)
                return parts.count >= 2 && isClosed(parts[parts.count - 1], in: parts[parts.count - 2], context)
            }
            return delete(closed)
        case .worktree:
            guard let path = item.paths.first, let repository = item.repository else { return "Nothing to remove" }
            let now = worktree(at: path, repository: repository, context)
            guard now.state == item.state else { return "It changed since the list was made. Nothing was removed." }
            let records = Worktree.read(root: path)?.records
            switch item.state {
            case .busy(let reason):
                return reason
            case .removable:
                guard let git = Git.path else { return "git was not found" }
                // A lock left by an agent that is gone would stop git from removing it.
                if let records, fm.fileExists(atPath: records + "/locked") {
                    _ = Shell.failure(git, ["-C", repository, "worktree", "unlock", path])
                }
                // git itself refuses if anything in it is modified or untracked. The branch stays.
                return Shell.failure(git, ["-C", repository, "worktree", "remove", path])
            case .uncommitted:
                do {
                    try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                } catch {
                    return error.localizedDescription
                }
                // The folder is in the Trash now. This only drops git's record of it; the branch stays.
                if let git = Git.path, let records {
                    try? fm.removeItem(atPath: records + "/locked")
                    _ = Shell.failure(git, ["-C", repository, "worktree", "prune"])
                }
                return nil
            }
        }
    }

    private static func delete(_ paths: [String]) -> String? {
        var failure: String?
        for path in paths where path.hasPrefix(home + "/") || path.hasPrefix(scratchRoot + "/") {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                failure = failure ?? error.localizedDescription
            }
        }
        return failure
    }

    static func abbreviate(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

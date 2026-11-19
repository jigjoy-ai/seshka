import Foundation

/// A git worktree other than the repository's main folder.
struct Worktree: Hashable {
    /// Its top folder.
    let root: String
    /// The folder's name.
    let name: String
    /// The branch checked out there, or nil when it is on no branch or cannot be read.
    let branch: String?
    /// The repository's main folder, when it can be told.
    let repository: String?
    /// The folder is gone, but something still runs in it.
    let missing: Bool

    /// The worktree `folder` is in, or nil when it is in a repository's main folder or in no repository.
    static func containing(_ folder: String) -> Worktree? {
        guard folder.hasPrefix("/") else { return nil }
        let fm = FileManager.default
        var at = folder
        while at.count > 1 {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: at + "/.git", isDirectory: &isDirectory) {
                // In the main folder .git is a directory. In a worktree it is a file that points into it.
                return isDirectory.boolValue ? nil : read(root: at)
            }
            at = (at as NSString).deletingLastPathComponent
        }
        // Deleted while a process still runs in it: nothing to read, but the path Claude Code gives its
        // own worktrees still says which one it was.
        if !fm.fileExists(atPath: folder), let marker = folder.range(of: "/.claude/worktrees/") {
            let name = folder[marker.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            guard !name.isEmpty else { return nil }
            let repository = String(folder[..<marker.lowerBound])
            return Worktree(root: repository + "/.claude/worktrees/" + name, name: name, branch: nil, repository: repository, missing: true)
        }
        return nil
    }

    /// Reads the worktree whose top folder is `root`, or nil when `root` is not one.
    static func read(root: String) -> Worktree? {
        guard let pointer = try? String(contentsOfFile: root + "/.git", encoding: .utf8),
              let line = pointer.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        // "<repository>/.git/worktrees/<name>". A submodule also has a .git file, pointing elsewhere.
        var records = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        if !records.hasPrefix("/") { records = root + "/" + records }
        guard let marker = records.range(of: "/.git/worktrees/") else { return nil }
        var branch: String?
        if let head = try? String(contentsOfFile: records + "/HEAD", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           head.hasPrefix("ref: refs/heads/") {
            branch = String(head.dropFirst("ref: refs/heads/".count))
        }
        return Worktree(root: root, name: (root as NSString).lastPathComponent, branch: branch,
                        repository: String(records[..<marker.lowerBound]), missing: false)
    }

    /// Where git keeps its records of this worktree: "<repository>/.git/worktrees/<name>".
    var records: String? {
        guard let pointer = try? String(contentsOfFile: root + "/.git", encoding: .utf8),
              let line = pointer.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? path : root + "/" + path
    }

    /// The branch, unless it only repeats the folder's name, as the ones Claude Code makes do.
    var label: String {
        guard let branch, branch != name, branch != "worktree-" + name else { return name }
        return "\(name) on \(branch)"
    }
}

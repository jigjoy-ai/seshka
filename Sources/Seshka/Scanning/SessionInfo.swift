import Foundation

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
        for dir in dirs {
            let file = "\(root)/\(dir)/\(sid).jsonl"
            guard fm.fileExists(atPath: file) else { continue }
            return (projectName(ofFolder: dir), title(inFile: file))
        }
        return (unknownProject, nil)
    }

    /// Claude Code names each project folder after its path, with every non-alphanumeric character
    /// replaced by "-". The name shown is that, without the home folder in front.
    static func projectName(ofFolder folder: String) -> String {
        var name = folder
        let prefix = folderName(ofPath: FileManager.default.homeDirectoryForCurrentUser.path)
        if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return name.isEmpty ? "~" : name
    }

    /// The name Claude Code gives the project folder of the sessions started in `path`.
    static func folderName(ofPath path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
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

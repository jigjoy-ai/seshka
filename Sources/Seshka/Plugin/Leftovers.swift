import Foundation

/// What closed sessions left running, in words: for the Claude Code plugin and the command line.
///
/// After every scan the list is also written to a file, one process a line with its folder in front.
/// The plugin's hook reads that file as a session starts, so that Claude is told what earlier
/// sessions left running in the folder it is about to work in. Reading a file takes no time; asking
/// seshka to scan again would hold every session's start up by a second or two.
enum Leftovers {
    static var file: URL {
        History.file.deletingLastPathComponent().appendingPathComponent("leftovers.tsv")
    }

    /// One process, as a line a person or Claude can read.
    static func line(_ proc: Proc, of group: SessionGroup) -> String {
        var parts = ["pid \(proc.pid)", proc.shortCommand]
        if !proc.ports.isEmpty { parts.append("port " + proc.ports.joined(separator: ", ")) }
        parts.append(formatBytes(proc.memory))
        parts.append("running for \(humanAge(proc.age))")
        parts.append("left by the session \"\(group.title ?? group.project)\"")
        // A tab or a line break in a command would break the file's own layout.
        return parts.joined(separator: " · ").replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    /// The groups that have something in this folder or below it; all of them without a folder.
    static func inside(_ folder: String?, _ groups: [SessionGroup]) -> [SessionGroup] {
        guard let folder, !folder.isEmpty else { return groups }
        let root = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return groups.compactMap { group in
            var group = group
            group.procs = group.procs.filter { $0.cwd == root || $0.cwd.hasPrefix(root + "/") }
            return group.procs.isEmpty ? nil : group
        }
    }

    static func write(_ groups: [SessionGroup]) {
        let lines = groups.flatMap { group in group.procs.map { "\($0.cwd)\t\(line($0, of: group))" } }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(to: file, atomically: true, encoding: .utf8)
    }
}

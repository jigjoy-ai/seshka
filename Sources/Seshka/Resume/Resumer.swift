import AppKit

/// Brings an ended session back: a terminal window in its folder, with `claude --resume` running.
@MainActor
enum Resumer {
    /// The terminals seshka knows how to hand a command to, by what they call themselves in TERM_PROGRAM.
    /// Each of them runs a .command file that is opened with it.
    private static let terminals = [
        "ghostty": "com.mitchellh.ghostty",
        "iTerm.app": "com.googlecode.iterm2",
        "Apple_Terminal": "com.apple.Terminal",
    ]

    nonisolated static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func copy(_ session: Resumable) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.command, forType: .string)
    }

    /// Opens the session in the terminal it ran in, or in the one macOS opens .command files with.
    /// Returns what went wrong, or nil.
    static func open(_ session: Resumable) -> String? {
        guard FileManager.default.fileExists(atPath: session.folder) else {
            return "Its folder is gone: \(Disk.abbreviate(session.folder))"
        }
        // A login shell, so that `claude` is found the way it is in a terminal the user opens.
        let script = "#!/bin/zsh -l\ncd \(quoted(session.folder)) || exit 1\nexec claude --resume \(session.id)\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Resume \(session.id.prefix(8)).command")
        do {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        } catch {
            return error.localizedDescription
        }
        let app = session.terminal.flatMap { terminals[$0] }.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let app {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else if !NSWorkspace.shared.open(file) {
            return "No terminal took it. The command is on the clipboard instead."
        }
        return nil
    }
}

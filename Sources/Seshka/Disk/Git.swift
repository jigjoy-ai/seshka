import Foundation

enum Git {
    /// Where git is, or nil when it is not installed. /usr/bin/git always exists, but without Apple's
    /// developer tools it only opens a window offering to install them.
    static let path: String? = {
        let fm = FileManager.default
        let tools = Shell.run("/usr/bin/xcode-select", ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tools.isEmpty, fm.fileExists(atPath: tools) { return "/usr/bin/git" }
        return ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first { fm.isExecutableFile(atPath: $0) }
    }()
}

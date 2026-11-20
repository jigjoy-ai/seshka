import AppKit
import Foundation
import IOKit
import IOKit.ps

/// What macOS has to be asked, and told, to keep a MacBook running with its lid closed.
///
/// Closing the lid puts a Mac to sleep whatever is running, and nothing an app may ask for on its own
/// changes that. The one setting that does is `pmset disablesleep`, and setting it takes root. So
/// seshka asks for the password once and adds a rule to sudo that allows exactly those two commands,
/// and nothing else, without a password.
enum Lid {
    static let rule = "/etc/sudoers.d/seshka-lid"
    private static let pmset = "/usr/bin/pmset"
    private static let commands = "\(pmset) disablesleep 1, \(pmset) disablesleep 0"

    // MARK: - Reading

    /// False on a Mac that has no lid to close.
    static var exists: Bool { power("AppleClamshellState") != nil }
    static var isClosed: Bool { power("AppleClamshellState") ?? false }
    /// Whether sleep is switched off right now, by seshka or by anything else.
    static var sleepDisabled: Bool { power("SleepDisabled") ?? false }

    /// A value macOS keeps about its power state. Read from the registry: no process is started.
    private static func power(_ key: String) -> Bool? {
        let domain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard domain != 0 else { return nil }
        defer { IOObjectRelease(domain) }
        return IORegistryEntryCreateCFProperty(domain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    /// How full the battery is and whether the Mac runs on it. Nil on a Mac without one.
    static var battery: (percent: Int, unplugged: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let about = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  about[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let now = about[kIOPSCurrentCapacityKey] as? Int, let full = about[kIOPSMaxCapacityKey] as? Int, full > 0 else { continue }
            return (now * 100 / full, about[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue)
        }
        return nil
    }

    // MARK: - Switching

    /// Whether seshka's rule is in place, so the switch works without a password.
    static var isAllowed: Bool { FileManager.default.fileExists(atPath: rule) }

    /// Switches sleep off or back on. Returns what went wrong, or nil.
    static func setSleepDisabled(_ disabled: Bool) -> String? {
        Shell.failure("/usr/bin/sudo", ["-n", pmset, "disablesleep", disabled ? "1" : "0"])
    }

    /// A closed lid does not always turn the screen off once sleep is disabled.
    static func turnDisplayOff() {
        _ = Shell.run(pmset, ["displaysleepnow"])
    }

    static func sleepNow() {
        _ = Shell.run(pmset, ["sleepnow"])
    }

    // MARK: - The rule

    enum Answer: Equatable {
        case done, cancelled
        case failed(String)
    }

    /// Adds the rule. macOS asks for an administrator's password; this waits for the answer.
    @MainActor
    static func allow() -> Answer {
        // By number, not by name: a user name may hold characters that mean something to sudo.
        let line = "#\(getuid()) ALL=(root) NOPASSWD: \(commands)"
        // Written aside and checked by visudo first: a broken file in that folder would break sudo itself.
        let script = "T=$(/usr/bin/mktemp /tmp/seshka-lid.XXXXXX) || exit 1; "
            + "/usr/bin/printf '%s\\n' '\(line)' > $T && /usr/sbin/visudo -c -q -f $T && /bin/mkdir -p /etc/sudoers.d && "
            + "/usr/bin/install -m 0440 -o root -g wheel $T \(rule); R=$?; /bin/rm -f $T; exit $R"
        let answer = asRoot(script, prompt: "seshka needs your password once, to let it switch this Mac's sleep off while Claude Code is working and back on when it is done. It adds a rule that allows that one setting and nothing else.")
        guard answer == .done else { return answer }
        return Shell.failure("/usr/bin/sudo", ["-n", "-l", pmset, "disablesleep", "1"]) == nil
            ? .done : .failed("The rule was added, but sudo does not accept it.")
    }

    /// Takes the rule away again.
    @MainActor
    static func forbid() -> Answer {
        asRoot("/bin/rm -f \(rule)", prompt: "seshka needs your password to remove the rule it added for the lid.")
    }

    @MainActor
    private static func asRoot(_ script: String, prompt: String) -> Answer {
        func quoted(_ text: String) -> String {
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let source = "do shell script \(quoted(script)) with administrator privileges with prompt \(quoted(prompt))"
        var error: NSDictionary?
        NSApp.activate(ignoringOtherApps: true)
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return .done }
        // -128 is the Cancel button.
        if error[NSAppleScript.errorNumber] as? Int == -128 { return .cancelled }
        return .failed(error[NSAppleScript.errorMessage] as? String ?? "macOS did not allow it.")
    }
}

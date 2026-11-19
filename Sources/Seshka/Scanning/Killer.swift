import Foundation

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

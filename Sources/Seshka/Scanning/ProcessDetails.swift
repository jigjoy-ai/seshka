import Foundation

/// Where a process sends its output.
enum Output {
    /// ".../claude-<user>/<project>/<session>/tasks/<command>.output"
    private static let pattern = #//claude-\d+/[^/]+/([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})/tasks/[^/]+$/#

    /// The session whose command output this process still writes, or nil.
    static func session(of pid: Int32) -> String? {
        for descriptor in [Int32(1), 2] {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { continue }
            let path = withUnsafeBytes(of: &info.pvip.vip_path) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            if let match = path.firstMatch(of: pattern) { return String(match.1) }
        }
        return nil
    }
}

enum Footprint {
    /// Physical memory footprint of a process in bytes, or 0 if it cannot be read.
    /// Unlike the RSS column of `ps`, this counts compressed and VM-backed memory,
    /// which is most of what an emulator or a virtual machine uses.
    static func bytes(of pid: Int32) -> UInt64 {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? info.ri_phys_footprint : 0
    }
}

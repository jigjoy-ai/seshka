import Foundation

extension CleanupLog {
    /// A few days of clean-ups of every kind, for drawing the History tab. Made-up names.
    static var sample: CleanupLog {
        let minute = 60.0, hour = 3600.0
        func at(_ ago: Double, _ reason: Cleanup.Reason, _ detail: String? = nil, _ items: [Cleanup.Item]) -> Cleanup {
            Cleanup(date: Date().addingTimeInterval(-ago), reason: reason, detail: detail, items: items)
        }
        let mb: UInt64 = 1_048_576
        return .made(of: [
            at(4 * minute, .sessionEnded, nil, [
                .init(pid: 75789, name: "node vite --port 3000", ports: ["3000"], memory: 412 * mb, place: "Add checkout to the storefront"),
                .init(pid: 75802, name: "esbuild --service=0.25.0 --ping", memory: 38 * mb, place: "Add checkout to the storefront"),
            ]),
            at(52 * minute, .idleAutomatic, "2 h", [
                .init(pid: 61120, name: "Claude Code session", memory: 640 * mb, place: "Refactor auth middleware", session: true),
                .init(pid: 61377, name: "npm run test -- --watch", memory: 221 * mb, place: "Refactor auth middleware"),
            ]),
            at(3 * hour, .click, nil, [
                .init(pid: 58214, name: "python -m http.server 8080", ports: ["8080"], memory: 24 * mb, place: "docs-site"),
            ]),
            at(26 * hour, .all, nil, [
                .init(pid: 40211, name: "next dev --turbopack", ports: ["3001"], memory: 980 * mb, place: "Upgrade to React 19"),
                .init(pid: 40377, name: "postgres -D /usr/local/var/pg", ports: ["5433"], memory: 156 * mb, place: "payments-api"),
                .init(pid: 40390, name: "tail -f logs/development.log", memory: 2 * mb, place: "payments-api"),
                .init(pid: 40402, name: "Google Chrome for Testing", memory: 1380 * mb, place: "Upgrade to React 19"),
                .init(pid: 40455, name: "tsc --watch --noEmit", memory: 318 * mb, place: "Upgrade to React 19"),
                .init(pid: 40470, name: "cargo watch -x run", memory: 97 * mb, place: "ingest-worker"),
                .init(pid: 40481, name: "redis-server *:6380", ports: ["6380"], memory: 12 * mb, place: "ingest-worker"),
            ]),
            at(50 * hour, .command, nil, [
                .init(pid: 31876, name: "bun run dev", ports: ["5173"], memory: 264 * mb, place: "marketing-site"),
            ]),
        ])
    }
}

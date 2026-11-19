import AppKit
import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var store: Store
    let showKillAll: Bool
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 8) {
            if confirming {
                Text("Kill \(store.killableOrphans.count) processes and free \(formatBytes(store.killableOrphans.reduce(0) { $0 + $1.memory }))?")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Button("Cancel") { confirming = false }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                Button("Kill them") {
                    confirming = false
                    store.killAllOrphans()
                }
                .buttonStyle(PillButtonStyle(tint: .red, filled: true))
            } else {
                Group {
                    if let freed = store.freed {
                        Label("Freed \(formatBytes(freed.bytes))  ·  \(freed.count) process\(freed.count == 1 ? "" : "es") killed",
                              systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.green)
                    } else if let last = store.lastScan {
                        Text("Updated \(Text(last, style: .relative)) ago")
                    } else {
                        Text("Scanning…")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                Spacer()
                if showKillAll, !store.killableOrphans.isEmpty {
                    Button("Kill all leftovers") { confirming = true }
                        .buttonStyle(PillButtonStyle(tint: .red))
                        .help(killAllHelp)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .onChange(of: showKillAll) { confirming = false }
    }

    private var killAllHelp: String {
        let skipped = store.orphanCount - store.killableOrphans.count
        return skipped > 0 ? "\(skipped) protected process\(skipped == 1 ? " is" : "es are") skipped" : "Kills every leftover process"
    }
}

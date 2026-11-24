import SwiftUI

/// The History tab: every clean-up of the last two weeks with what was killed and why, newest first.
struct LogView: View {
    @EnvironmentObject private var store: Store
    @State private var confirming = false

    var body: some View {
        let entries = store.log.entries
        Group {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Nothing killed yet").font(.system(size: 13, weight: .semibold))
                    Text("Whatever seshka kills is listed here with the reason: a click of yours, a session that sat idle too long, or one that ended.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        top(entries)
                        ForEach(entries) { cleanup in
                            CleanupCard(cleanup: cleanup)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .onAppear { store.reloadLog() }
    }

    private func top(_ entries: [Cleanup]) -> some View {
        HStack(spacing: 8) {
            if confirming {
                Text("Clear the history?").font(.system(size: 11.5, weight: .medium))
                Spacer()
                Button("Cancel") { confirming = false }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                Button("Clear") {
                    confirming = false
                    store.clearLog()
                }
                .buttonStyle(PillButtonStyle(tint: .red, filled: true))
            } else {
                let automatic = entries.filter(\.reason.automatic).count
                Text("What was killed in the last \(CleanupLog.daysKept) days, and why  ·  \(automatic) of \(entries.count) automatic")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Button("Clear") { confirming = true }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                    .help("Forget the history. It is kept on this Mac only, in \(Disk.abbreviate(CleanupLog.file.path))")
            }
        }
        .padding(.horizontal, 4)
    }
}

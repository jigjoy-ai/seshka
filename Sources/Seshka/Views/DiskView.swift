import SwiftUI

/// What sessions left on disk: the worktrees Claude Code made, the scratch files of closed sessions,
/// and caches that fill again by themselves. Nothing here is removed without a click.
struct DiskView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let worktrees = store.disk(.worktree), scratch = store.disk(.scratch), caches = store.disk(.cache)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                if !worktrees.isEmpty {
                    section("WORKTREES", "Git worktrees Claude Code made for its agents. Removing one keeps its branch and its commits.", worktrees)
                }
                if !scratch.isEmpty {
                    section("SCRATCH FILES", "Temporary files and command output of sessions that are closed.", scratch)
                }
                if !caches.isEmpty {
                    section("CACHES", "Downloads that developer tools fetch again when they need them.", caches)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .onAppear {
            // Measuring takes a minute or two, so not on every visit. The refresh button always does it.
            if store.diskRead.map({ Date().timeIntervalSince($0) > 600 }) ?? true { store.refreshDisk() }
        }
    }

    private var summary: some View {
        let nothing = store.disk.isEmpty || (store.diskRemovable == 0 && !store.diskScanning)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                if nothing {
                    Text(store.diskScanning ? "Looking…" : "Nothing to clean up")
                        .font(.system(size: 13, weight: .semibold))
                } else if store.diskRemovable == 0 {
                    Text("Measuring…").font(.system(size: 13, weight: .semibold))
                } else {
                    Text(store.diskScanning
                         ? "At least \(formatBytes(store.diskRemovable)) can be freed"
                         : "\(formatBytes(store.diskRemovable)) can be freed")
                        .font(.system(size: 13, weight: .semibold))
                        .contentTransition(.numericText())
                }
                Text(store.diskFreed > 0
                     ? "Freed \(formatBytes(store.diskFreed)) so far. Nothing is removed without a click."
                     : "Nothing is removed without a click.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(store.diskFreed > 0 ? Color.green : Color.secondary)
            }
            Spacer()
            if store.diskScanning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func section(_ title: String, _ about: String, _ items: [DiskItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(items.contains { $0.bytes != nil } ? formatBytes(items.reduce(0) { $0 + ($1.bytes ?? 0) }) : "…")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(about)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                ForEach(items) { item in
                    Divider().opacity(0.4)
                    DiskRow(item: item)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct DiskRow: View {
    @EnvironmentObject private var store: Store
    let item: DiskItem
    @State private var confirming = false

    var body: some View {
        let removing = store.removing.contains(item.id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(item.bytes.map(formatBytes) ?? "…")
                    .font(.system(size: 10.5, weight: (item.bytes ?? 0) >= 1_073_741_824 ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle((item.bytes ?? 0) >= 1_073_741_824 ? Color.orange : Color.secondary)
                    .fixedSize()
                if removing {
                    ProgressView().controlSize(.small)
                } else if case .busy(let reason) = item.state {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                        .help(reason)
                } else if confirming {
                    Button("Cancel") { confirming = false }
                        .buttonStyle(PillButtonStyle(tint: .secondary))
                    Button(confirmLabel) {
                        confirming = false
                        store.remove(item)
                    }
                    .buttonStyle(PillButtonStyle(tint: .red, filled: true))
                } else {
                    Button(label) { confirming = true }
                        .buttonStyle(PillButtonStyle(tint: .red))
                        .disabled(item.bytes == nil)
                }
            }
            if let line = line(removing: removing) {
                Text(line.text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(line.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(removing ? 0.5 : 1)
    }

    private var label: String {
        switch item.kind {
        case .worktree: return item.state == .uncommitted ? "Trash" : "Remove"
        case .scratch: return "Delete"
        case .cache: return "Clear"
        }
    }

    private var confirmLabel: String {
        switch item.kind {
        case .worktree: return item.state == .uncommitted ? "Move to Trash" : "Remove it"
        case .scratch: return "Delete them"
        case .cache: return "Clear it"
        }
    }

    /// The line under a row: what went wrong, what removing it does, or why it cannot be removed.
    private func line(removing: Bool) -> (text: String, color: Color)? {
        if let failure = store.diskFailure, failure.id == item.id { return (failure.reason, .red) }
        if case .busy(let reason) = item.state { return (reason + ".", .secondary) }
        if confirming {
            switch item.kind {
            case .worktree:
                return item.state == .uncommitted
                    ? ("The folder goes to the Trash with everything in it. Its branch and its commits stay.", .primary)
                    : ("The folder is deleted. Its branch and its commits stay.", .primary)
            case .scratch:
                return ("Deleted for good. The conversations themselves are kept elsewhere and stay.", .primary)
            case .cache:
                return (item.note ?? "Deleted for good.", .primary)
            }
        }
        if item.kind == .worktree, item.state == .uncommitted {
            return ("Has changes that were never committed.", .orange)
        }
        return nil
    }
}

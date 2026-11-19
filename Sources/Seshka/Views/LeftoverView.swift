import SwiftUI

struct SessionList: View {
    let groups: [SessionGroup]
    /// Show the doll closing when the list empties (the leftover tab), instead of a plain checkmark.
    let celebrates: Bool
    let emptyTitle: String
    let emptyDetail: String

    var body: some View {
        if groups.isEmpty {
            Group {
                if celebrates {
                    CleanView(title: emptyTitle, detail: emptyDetail)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.green)
                        Text(emptyTitle).font(.system(size: 13, weight: .semibold))
                        Text(emptyDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(groups) { group in
                        SessionCard(group: group)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .transition(.opacity)
        }
    }
}

/// The empty leftover list. Right after a clean-up the doll is shown open and snaps shut.
struct CleanView: View {
    @EnvironmentObject private var store: Store
    let title: String
    let detail: String
    @State private var closed = false

    var body: some View {
        let justCleaned = store.freed != nil
        VStack(spacing: 6) {
            Matryoshka(openness: closed || !justCleaned ? 0 : 1)
                .frame(width: 132, height: 132)
                .padding(.bottom, 6)
            if let freed = store.freed {
                Text("Freed \(formatBytes(freed.bytes))")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text("\(freed.count) process\(freed.count == 1 ? "" : "es") killed. Nothing left running.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            // Held open for a beat, then about a second and a half to drop shut and settle.
            withAnimation(.spring(response: 1.1, dampingFraction: 0.55).delay(0.6)) { closed = true }
        }
    }
}

struct SessionCard: View {
    @EnvironmentObject private var store: Store
    let group: SessionGroup

    private var killable: [Proc] { group.procs.filter { !store.isProtected($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.title ?? group.project)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                            // A long worktree name gives way before the title does.
                            .layoutPriority(1)
                        if let worktree = group.worktree {
                            WorktreeTag(worktree: worktree)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !killable.isEmpty {
                    Button("Kill \(killable.count)") { store.kill(session: group) }
                        .buttonStyle(PillButtonStyle(tint: .red))
                        .help(group.worktree == nil
                              ? "Kill every process of this session, except protected ones"
                              : "Kill every process this session left in this worktree, except protected ones")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().opacity(0.4)

            ForEach(group.procs) { proc in
                ProcRow(proc: proc)
                    .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var subtitle: String {
        var parts: [String] = []
        if group.title != nil { parts.append(group.project) }
        parts.append(group.shortID)
        parts.append("\(group.procs.count) process\(group.procs.count == 1 ? "" : "es")")
        parts.append(formatBytes(group.memory))
        return parts.joined(separator: "  ·  ")
    }
}

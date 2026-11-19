import SwiftUI

/// Marks a card or a row as belonging to a git worktree: its folder, and its branch when that says more.
struct WorktreeTag: View {
    let worktree: Worktree

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 8.5, weight: .semibold))
            Text(worktree.label).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(worktree.missing ? Color.orange : Color.purple)
        .background(Capsule().fill((worktree.missing ? Color.orange : Color.purple).opacity(0.16)))
        .help(worktree.missing
              ? "A git worktree that has been deleted. What ran in it is still running."
              : "Runs in the git worktree \(Disk.abbreviate(worktree.root))")
    }
}

/// A session's processes. When some run in git worktrees, each worktree's are listed under its name.
struct ProcRows: View {
    let procs: [Proc]

    var body: some View {
        let worktrees = procs.compactMap(\.worktree).reduce(into: [Worktree]()) { if !$0.contains($1) { $0.append($1) } }
        ForEach(procs.filter { $0.worktree == nil }) { proc in
            ProcRow(proc: proc).transition(.opacity)
        }
        ForEach(worktrees.sorted { $0.name < $1.name }, id: \.root) { worktree in
            HStack {
                WorktreeTag(worktree: worktree)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 2)
            ForEach(procs.filter { $0.worktree == worktree }) { proc in
                ProcRow(proc: proc).transition(.opacity)
            }
        }
    }
}

struct ProcRow: View {
    @EnvironmentObject private var store: Store
    let proc: Proc
    @State private var hovering = false
    @State private var expanded = false

    var body: some View {
        let protected = store.isProtected(proc)
        let killing = store.killing.contains(proc.pid)
        let heavy = proc.memory >= 500 * 1_048_576

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Text(humanAge(proc.age))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)
                if let port = proc.ports.first {
                    Text(proc.ports.count > 1 ? ":\(port) +\(proc.ports.count - 1)" : ":\(port)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.blue.opacity(0.16)))
                }
                Text(proc.shortCommand)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(killing ? 0.4 : 1)
                Spacer(minLength: 4)
                Text(formatBytes(proc.memory))
                    .font(.system(size: 10.5, weight: heavy ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(heavy ? Color.orange : Color.secondary)
                    .fixedSize()
                    .help("Memory in use")
                if killing {
                    ProgressView().controlSize(.small)
                } else if protected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("Protected: skipped by Kill all and Kill session")
                } else {
                    Button {
                        store.kill([proc])
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                    .help("Kill this process")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }

            if expanded {
                details(protected: protected, killing: killing)
            }
        }
        .background(hovering || expanded ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering = $0 }
    }

    private func details(protected: Bool, killing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailLine(label: "PID", value: "\(proc.pid)   parent \(proc.ppid)   running \(humanAge(proc.age))", copyValue: "\(proc.pid)")
            DetailLine(label: "Memory", value: formatBytes(proc.memory), copyValue: formatBytes(proc.memory))
            if !proc.helpers.isEmpty {
                let count = proc.helpers.count
                DetailLine(
                    label: "Helpers",
                    value: "\(count) helper process\(count == 1 ? "" : "es"), counted in the memory and killed with it",
                    copyValue: proc.helpers.map { String($0.pid) }.joined(separator: " ")
                )
            }
            if !proc.ports.isEmpty {
                DetailLine(label: "Ports", value: proc.ports.joined(separator: ", "), copyValue: proc.ports.joined(separator: " "))
            }
            if !proc.cwd.isEmpty {
                DetailLine(label: "Folder", value: abbreviate(proc.cwd), copyValue: proc.cwd)
            }
            DetailLine(label: "Command", value: proc.command.replacingOccurrences(of: "\\012", with: " "), copyValue: proc.command)
            HStack(spacing: 6) {
                if protected {
                    Button("Unprotect") { store.unprotect(proc) }
                        .buttonStyle(PillButtonStyle(tint: .secondary))
                } else {
                    Button("Protect \(proc.executable)") { store.protect(proc) }
                        .buttonStyle(PillButtonStyle(tint: .secondary))
                        .help("Never include \(proc.executable) in Kill all or Kill session")
                }
                Spacer()
                Button("Kill") { store.kill([proc]) }
                    .buttonStyle(PillButtonStyle(tint: .red))
                    .disabled(killing)
            }
            .padding(.top, 2)
        }
        .padding(.leading, 26)
        .padding(.trailing, 10)
        .padding(.bottom, 8)
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct DetailLine: View {
    let label: String
    let value: String
    let copyValue: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copyToClipboard(copyValue)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(copied ? Color.green : Color.secondary)
            .help("Copy")
        }
    }
}

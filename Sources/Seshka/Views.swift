import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var updater: Updater
    @State private var tab: Tab = .orphans
    @State private var spin = 0.0

    enum Tab: Hashable { case orphans, live, settings, about }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Group {
                switch tab {
                case .orphans:
                    SessionList(
                        groups: store.orphans,
                        celebrates: true,
                        emptyTitle: "No leftover processes",
                        emptyDetail: "Nothing started by a closed Claude Code session is still running."
                    )
                case .live:
                    SessionList(
                        groups: store.live,
                        celebrates: false,
                        emptyTitle: "No background processes",
                        emptyDetail: "Running sessions have nothing in the background older than a minute."
                    )
                case .settings:
                    SettingsView()
                case .about:
                    AboutView()
                }
            }
            .frame(maxHeight: .infinity)
            Divider().opacity(0.4)
            FooterView(showKillAll: tab == .orphans)
        }
        .frame(width: 480, height: 600)
        .onAppear { store.refresh() }
        // One full turn per scan. A finite animation on purpose: a repeating one kept
        // running after the scan ended and pinned the main thread redrawing the list.
        .onChange(of: store.scanning) { _, scanning in
            if scanning {
                withAnimation(.easeInOut(duration: 0.6)) { spin += 360 }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Matryoshka(openness: store.orphanCount > 0 ? 1 : 0)
                .frame(width: 36, height: 36)
                .animation(.spring(response: 1.1, dampingFraction: 0.55).delay(0.6), value: store.orphanCount > 0)
            VStack(alignment: .leading, spacing: 1) {
                Text("seshka").font(.system(size: 15, weight: .semibold))
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let version = updater.availableVersion {
                Button("Update to \(version)") { updater.check() }
                    .buttonStyle(PillButtonStyle(tint: .green))
                    .help("A new version of seshka is ready")
            }
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(spin))
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let count = store.orphanCount
        if count == 0 { return "All clean" }
        let sessions = store.orphans.count
        return "\(count) leftover process\(count == 1 ? "" : "es") from \(sessions) closed session\(sessions == 1 ? "" : "s")  ·  \(formatBytes(store.orphanMemory))"
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            TabButton(title: "Leftover", icon: "moon.zzz", count: store.orphanCount, selected: tab == .orphans) { tab = .orphans }
            TabButton(title: "Live", icon: "bolt", count: store.liveCount, selected: tab == .live) { tab = .live }
            TabButton(title: "Settings", icon: "gearshape", count: nil, selected: tab == .settings) { tab = .settings }
            TabButton(title: "About", icon: "info.circle", count: nil, selected: tab == .about) { tab = .about }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Session list

private struct SessionList: View {
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
private struct CleanView: View {
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

private struct SessionCard: View {
    @EnvironmentObject private var store: Store
    let group: SessionGroup

    private var killable: [Proc] { group.procs.filter { !store.isProtected($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title ?? group.project)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !killable.isEmpty {
                    Button("Kill \(killable.count)") { store.kill(session: group) }
                        .buttonStyle(PillButtonStyle(tint: .red))
                        .help("Kill every process of this session, except protected ones")
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

private struct ProcRow: View {
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

private struct DetailLine: View {
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

// MARK: - Footer

private struct FooterView: View {
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

// MARK: - Settings

private struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newPattern = ""
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                section("REFRESH") {
                    HStack {
                        Text("Check for processes every").font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $store.interval) {
                            Text("10 s").tag(10)
                            Text("30 s").tag(30)
                            Text("1 min").tag(60)
                            Text("5 min").tag(300)
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }

                section("STARTUP") {
                    Toggle(isOn: Binding(
                        get: { store.launchesAtLogin },
                        set: { loginError = store.setLaunchAtLogin($0) }
                    )) {
                        Text("Launch at login").font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    if let loginError {
                        Text(loginError).font(.system(size: 10.5)).foregroundStyle(.red)
                    }
                }

                section("PROTECTED") {
                    Text("A process whose command contains one of these is skipped by Kill all and Kill session.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(store.protectedPatterns, id: \.self) { pattern in
                        HStack {
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(pattern).font(.system(size: 11.5, design: .monospaced))
                            Spacer()
                            Button {
                                store.protectedPatterns.removeAll { $0 == pattern }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Stop protecting")
                        }
                    }
                    HStack {
                        TextField("e.g. docker", text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                            .onSubmit(addPattern)
                        Button("Add", action: addPattern)
                            .buttonStyle(PillButtonStyle(tint: .secondary))
                            .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func addPattern() {
        let pattern = newPattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        if !store.protectedPatterns.contains(pattern) { store.protectedPatterns.append(pattern) }
        newPattern = ""
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var updater: Updater

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Matryoshka(openness: store.orphanCount > 0 ? 1 : 0)
                        .frame(width: 92, height: 92)
                    Text("seshka").font(.system(size: 20, weight: .bold))
                    Text("Version \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Kill what Claude Code left behind.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding(.top, 6)

                card {
                    HStack {
                        Text("Updates").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Check for Updates…") { updater.check() }
                            .buttonStyle(PillButtonStyle(tint: .secondary))
                            .disabled(!updater.canCheck)
                    }
                    Toggle(isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 })) {
                        Text("Check automatically").font(.system(size: 12))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                card {
                    Text("Made by lotus from the JigJoy team")
                        .font(.system(size: 12, weight: .medium))
                    VStack(alignment: .leading, spacing: 7) {
                        link("lotus015 on GitHub", "https://github.com/lotus015")
                        link("JigJoy on GitHub", "https://github.com/jigjoy-ai")
                        link("Source code", "https://github.com/jigjoy-ai/seshka")
                        link("seshka.dev", "https://seshka.dev")
                    }
                }

                card {
                    Text("How it works").font(.system(size: 12, weight: .medium))
                    Text("seshka finds everything Claude Code started by looking for CLAUDECODE=1 in each process's environment. A process counts as leftover once the Claude Code process that started it is gone. Nothing leaves your Mac.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Free and open source, under the MIT license.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func link(_ title: String, _ address: String) -> some View {
        Link(destination: URL(string: address)!) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                Text(title).font(.system(size: 12))
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Controls

private struct TabButton: View {
    let title: String
    let icon: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).font(.system(size: 11.5, weight: .medium))
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(selected ? 0.18 : 0.1)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PillButtonStyle: ButtonStyle {
    var tint: Color
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : (tint == .secondary ? Color.primary : tint))
            .background(Capsule().fill(filled ? tint : (tint == .secondary ? Color.primary.opacity(0.1) : tint.opacity(0.16))))
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .foregroundStyle(.secondary)
            .contentShape(Circle())
    }
}

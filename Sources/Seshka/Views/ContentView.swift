import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var updater: Updater
    @State var tab: Tab = .orphans
    @State private var spin = 0.0

    enum Tab: Hashable { case orphans, sessions, disk, settings, about }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let version = updater.availableVersion {
                updateBanner(version)
            }
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
                case .sessions:
                    SessionsView()
                case .disk:
                    DiskView()
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
                HStack(spacing: 8) {
                    Text("seshka").font(.system(size: 15, weight: .semibold)).fixedSize()
                    // Only while something is working. In the minute after, the Mac is still up, but not for long.
                    if case .holding(let working) = store.awake, working > 0 {
                        AwakeSign()
                            .help("The Mac stays awake with its lid closed while \(working) session\(working == 1 ? " is" : "s are") working, and sleeps when the last one finishes")
                            .transition(.opacity)
                    }
                }
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.refresh()
                if tab == .disk { store.refreshDisk() }
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

    /// A downloaded update, waiting for a restart. Across the whole width, so it is not missed.
    private func updateBanner(_ version: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("seshka \(version) is ready").font(.system(size: 12, weight: .semibold))
                Text("Restart to start using it. It takes a few seconds.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restart now") { updater.applyUpdate() }
                .buttonStyle(PillButtonStyle(tint: .green, filled: true))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.green.opacity(0.3)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var summary: String {
        let count = store.orphanCount
        if count == 0 { return "All clean" }
        // A session that worked in several worktrees has a card for each, and is still one session.
        let sessions = Set(store.orphans.map(\.sessionID)).count
        return "\(count) leftover process\(count == 1 ? "" : "es") from \(sessions) closed session\(sessions == 1 ? "" : "s")  ·  \(formatBytes(store.orphanMemory))"
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            TabButton(title: "Leftover", icon: "moon.zzz", count: store.orphanCount, selected: tab == .orphans) { tab = .orphans }
            TabButton(title: "Sessions", icon: "terminal", count: store.idleSessions.count, selected: tab == .sessions) { tab = .sessions }
            TabButton(title: "Disk", icon: "internaldrive", count: nil, selected: tab == .disk) { tab = .disk }
            TabButton(title: "Settings", icon: "gearshape", count: nil, selected: tab == .settings, iconOnly: true) { tab = .settings }
            TabButton(title: "About", icon: "info.circle", count: nil, selected: tab == .about, iconOnly: true) { tab = .about }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

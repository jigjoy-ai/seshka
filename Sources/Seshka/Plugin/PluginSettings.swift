import AppKit
import SwiftUI

/// The part of Settings about the Claude Code plugin: what seshka does when a session ends.
struct PluginSettings: View {
    @EnvironmentObject private var store: Store
    @State private var copied = false

    /// Typed in a terminal. Inside a session the same is `/plugin install seshka --marketplace jigjoy-ai/seshka`.
    static let install = "claude plugin marketplace add jigjoy-ai/seshka && claude plugin install seshka@seshka"

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Kill what it left running").font(.system(size: 12, weight: .medium))
                Text(caption)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $store.cleansEndedSessions)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        if let last = store.lastEndClean {
            Text("Killed \(last.count) process\(last.count == 1 ? "" : "es") left by \(last.title) at \(last.date.formatted(date: .omitted, time: .shortened)).")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Divider().opacity(0.4)
        HStack(alignment: .center) {
            Text(plugin)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(copied ? "Copied" : "Copy install command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.install, forType: .string)
                copied = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    copied = false
                }
            }
            .buttonStyle(PillButtonStyle(tint: .secondary))
            .help(Self.install)
        }
    }

    private var caption: String {
        store.cleansEndedSessions
            ? "When a Claude Code session ends, however it ends, its leftover processes are killed. Protected ones are skipped."
            : "Off. Leftover processes wait for you on the Leftover tab."
    }

    /// Without the plugin Claude Code never says that a session ended, and the switch does nothing.
    private var plugin: String {
        guard let heard = store.pluginHeard else {
            return "Needs the seshka plugin for Claude Code. It has not been heard from yet."
        }
        return "The Claude Code plugin last reported a session \(humanAge(max(0, Int(Date().timeIntervalSince(heard))))) ago."
    }
}

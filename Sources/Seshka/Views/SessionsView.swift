import SwiftUI

/// Every open Claude Code session: whether it is working or waiting, for how long, and what it holds.
struct SessionsView: View {
    @EnvironmentObject private var store: Store
    @State private var confirming = false
    @State private var customizing = false

    /// The waiting times offered as chips, in minutes. Anything else is set under Custom.
    private static let presets = [30, 60, 120, 240, 480]

    var body: some View {
        VStack(spacing: 0) {
            idleCard
            if store.sessions.isEmpty && store.live.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No sessions open").font(.system(size: 13, weight: .semibold))
                    Text("Claude Code sessions show up here while they run.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summary
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sessions) { session in
                            RunningSessionCard(session: session)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                        // Background processes whose session could not be matched to an open one.
                        ForEach(store.live) { group in
                            SessionCard(group: group)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    /// How long a session may wait, and whether seshka ends the ones that wait longer on its own.
    private var idleCard: some View {
        let isCustom = customizing || !Self.presets.contains(store.idleLimitMinutes)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("End idle sessions automatically")
                        .font(.system(size: 12, weight: .medium))
                    Text(store.endsIdleSessions
                         ? "Sessions waiting longer than \(formatLimit(store.idleLimitMinutes)) are ended on their own."
                         : "Off. Sessions are only ended when you click.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $store.endsIdleSessions)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 5) {
                ForEach(Self.presets, id: \.self) { minutes in
                    Chip(title: chipTitle(minutes), selected: !isCustom && store.idleLimitMinutes == minutes) {
                        customizing = false
                        store.idleLimitMinutes = minutes
                    }
                }
                Chip(title: "Custom", selected: isCustom) { customizing = true }
            }

            if isCustom {
                HStack {
                    Text("Idle after").font(.system(size: 11.5))
                    Spacer()
                    Text(formatLimit(store.idleLimitMinutes))
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    // Steps of 15 minutes, from half an hour up to a week.
                    Stepper("", value: $store.idleLimitMinutes, in: Store.minimumIdleLimit...10080, step: 15)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }

            if let last = store.lastAutoEnd {
                Text("Ended \(last.count) idle session\(last.count == 1 ? "" : "s") at \(last.date.formatted(date: .omitted, time: .shortened)). Bring one back with claude --resume.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func chipTitle(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    private var summary: some View {
        let idle = store.idleSessions
        return HStack(spacing: 8) {
            if confirming {
                Text("End \(idle.count) idle session\(idle.count == 1 ? "" : "s")?")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Button("Cancel") { confirming = false }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                Button("Kill idle") {
                    confirming = false
                    store.killIdleSessions()
                }
                .buttonStyle(PillButtonStyle(tint: .red, filled: true))
            } else {
                Text("\(store.sessions.count) open  ·  \(idle.count) idle over \(formatLimit(store.idleLimitMinutes))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !idle.isEmpty {
                    Button("Kill idle") { confirming = true }
                        .buttonStyle(PillButtonStyle(tint: .red))
                        .help("End every session that has been waiting longer than \(formatLimit(store.idleLimitMinutes)). They can be resumed later.")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 9)
    }
}

/// One choice in a row of choices.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08)))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct RunningSessionCard: View {
    @EnvironmentObject private var store: Store
    let session: RunningSession
    @State private var confirming = false

    private var overLimit: Bool { (session.idleSeconds() ?? -1) >= store.idleLimitMinutes * 60 }

    var body: some View {
        let killing = store.killing.contains(session.process.pid)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title ?? session.project)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if killing {
                    ProgressView().controlSize(.small)
                } else if confirming {
                    Button("Cancel") { confirming = false }
                        .buttonStyle(PillButtonStyle(tint: .secondary))
                    Button("End it") {
                        confirming = false
                        store.kill(running: session)
                    }
                    .buttonStyle(PillButtonStyle(tint: .red, filled: true))
                } else {
                    Button("Kill") {
                        // A session that is working, or whose state is unknown, takes a second click.
                        if session.status == .idle {
                            store.kill(running: session)
                        } else {
                            confirming = true
                        }
                    }
                    .buttonStyle(PillButtonStyle(tint: .red))
                    .help("End this session and what it has running. It can be resumed later with claude --resume.")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .opacity(killing ? 0.5 : 1)

            if !session.procs.isEmpty {
                Divider().opacity(0.4)
                ProcRows(procs: session.procs)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var dotColor: Color {
        switch session.status {
        case .busy: return .green
        case .idle: return overLimit ? .orange : .secondary
        case .other, .unknown: return Color.secondary.opacity(0.4)
        }
    }

    private var statusText: String {
        switch session.status {
        case .busy: return "working"
        case .idle: return session.idleSeconds().map { "idle \(humanAge($0))" } ?? "idle"
        case .other(let name): return name
        case .unknown: return "status unknown"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if session.title != nil { parts.append(session.project) }
        parts.append(statusText)
        parts.append("open \(humanAge(session.process.age))")
        parts.append(formatBytes(session.memory))
        if !session.procs.isEmpty {
            parts.append("\(session.procs.count) in background")
        }
        return parts.joined(separator: "  ·  ")
    }
}

import SwiftUI

/// The switch that keeps the Mac awake with its lid closed while Claude Code works, and what goes with it.
struct AwakeSettings: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep working with the lid closed").font(.system(size: 12, weight: .medium))
                Text(AwakeSettings.caption(store.awake))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { store.staysAwake }, set: { store.setStaysAwake($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        HStack {
            Text("Stop when the battery is below").font(.system(size: 12))
            Spacer()
            Picker("", selection: $store.awakeBatteryFloor) {
                ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
            .labelsHidden()
            .frame(width: 90)
        }
        if let failure = store.awakeFailure {
            Text(failure).font(.system(size: 10.5)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
        if !Lid.isAllowed {
            note("Turning it on asks for your password once. seshka adds a rule to sudo that lets it switch this Mac's sleep off and on, and nothing else.")
        } else if !store.staysAwake {
            HStack(alignment: .firstTextBaseline) {
                note("seshka may switch this Mac's sleep off and on without a password.")
                Spacer()
                Button("Remove") { store.forgetAwakePermission() }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                    .help("Removes the rule seshka added to sudo. It asks for your password.")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func caption(_ awake: Awake) -> String {
        switch awake {
        case .off:
            return "Off. A closed lid puts the Mac to sleep, whatever Claude is doing."
        case .waiting:
            return "On. Nothing is working, so the Mac sleeps as usual."
        case .holding(let working) where working > 0:
            return "Staying awake for \(working) working session\(working == 1 ? "" : "s"). The Mac sleeps when the last one finishes."
        case .holding:
            return "Staying awake a little longer, in case a session carries on."
        case .paused(let why):
            return "Not staying awake: \(why)."
        }
    }
}

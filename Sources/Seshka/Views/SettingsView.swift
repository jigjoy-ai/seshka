import SwiftUI

struct SettingsView: View {
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

                if Lid.exists {
                    section("LID CLOSED") { AwakeSettings() }
                }

                section("WHEN A SESSION ENDS") { PluginSettings() }

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

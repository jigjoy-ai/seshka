import SwiftUI

struct AboutView: View {
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
                    if let ready = updater.availableVersion {
                        HStack {
                            Text("Version \(ready) is ready").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Install and restart") { updater.applyUpdate() }
                                .buttonStyle(PillButtonStyle(tint: .green))
                        }
                    } else {
                        HStack {
                            Text("Updates").font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Check for Updates…") { updater.check() }
                                .buttonStyle(PillButtonStyle(tint: .secondary))
                                .disabled(!updater.canCheck)
                        }
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
                    HStack {
                        Text("How it works").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Show the tour") { Welcome.show(store: store) }
                            .buttonStyle(PillButtonStyle(tint: .secondary))
                    }
                    Text("seshka finds everything Claude Code started by looking for CLAUDECODE=1 in each process's environment. Where macOS hides the environment, it goes by the file the process still writes its output to, and by what the process started. A process counts as leftover once the Claude Code process that started it is gone. Nothing leaves your Mac.")
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

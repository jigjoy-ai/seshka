import SwiftUI

/// The sessions seshka ended lately, each with a way back.
struct ResumeList: View {
    @EnvironmentObject private var store: Store
    @State private var failure: String?
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ENDED BY SESHKA")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.ended) { session in
                    if session.id != store.ended.first?.id { Divider().opacity(0.4) }
                    row(session)
                }
                if let failure {
                    Text(failure)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    private func row(_ session: Resumable) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text("\(session.project)  ·  ended \(humanAge(max(0, Int(Date().timeIntervalSince(session.ended))))) ago")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                Resumer.copy(session)
                copied = session.id
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if copied == session.id { copied = nil }
                }
            } label: {
                Image(systemName: copied == session.id ? "checkmark" : "doc.on.doc").font(.system(size: 10.5))
            }
            .buttonStyle(IconButtonStyle())
            .help("Copy the command that resumes it: \(session.command)")
            Button("Resume") {
                failure = Resumer.open(session)
                if failure == nil { store.forget(session) } else { Resumer.copy(session) }
            }
            .buttonStyle(PillButtonStyle(tint: .green))
            .help("Open a terminal in \(Disk.abbreviate(session.folder)) and resume this session")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

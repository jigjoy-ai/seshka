import SwiftUI

/// One line on what was cleaned up lately, with the button that opens the card. Not there before the
/// first clean-up: there is nothing to say yet.
struct WeekRow: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        let week = store.history.week()
        if !week.isEmpty {
            let period = store.history.period()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleaned up \(period)")
                        .font(.system(size: 12, weight: .medium))
                    Text(summary(week))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                Button("Share") { Share.show(store: store) }
                    .buttonStyle(PillButtonStyle(tint: .secondary))
                    .help("Make a picture of these numbers to post. Nothing but the numbers is on it.")
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    private func summary(_ week: History.Tally) -> String {
        var parts: [String] = []
        if week.memory > 0 { parts.append("\(formatBytes(week.memory)) of memory") }
        if week.disk > 0 { parts.append("\(formatBytes(week.disk)) of disk") }
        if week.processes > 0 { parts.append("\(week.processes) process\(week.processes == 1 ? "" : "es")") }
        if week.sessions > 0 { parts.append("\(week.sessions) session\(week.sessions == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

import SwiftUI

/// One clean-up in the History tab: who decided and why on top, what was killed below.
struct CleanupCard: View {
    let cleanup: Cleanup
    @State private var expanded = false

    /// Longer lists are folded: a Kill all of thirty processes should not push everything else away.
    private static let shown = 4

    var body: some View {
        let items = expanded || cleanup.items.count <= Self.shown + 1 ? cleanup.items : Array(cleanup.items.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                tag
                VStack(alignment: .leading, spacing: 2) {
                    Text(cleanup.why)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cleanup.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(Self.when(cleanup.date))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().opacity(0.4)

            ForEach(items) { item in
                row(item)
            }
            if items.count < cleanup.items.count {
                Button("Show \(cleanup.items.count - items.count) more") { expanded = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .pointsOnHover()
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }

    /// Who decided: seshka on its own, or the user.
    private var tag: some View {
        let automatic = cleanup.reason.automatic
        return Text(automatic ? "AUTO" : "YOU")
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(automatic ? Color.orange : Color.secondary)
            .background(Capsule().fill((automatic ? Color.orange : Color.primary).opacity(automatic ? 0.18 : 0.1)))
            .help(automatic ? "seshka did this on its own, because a switch you turned on told it to" : "You asked for this")
    }

    private func row(_ item: Cleanup.Item) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(item.name)
                    .font(.system(size: 11, weight: item.session ? .medium : .regular, design: item.session ? .default : .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail(item))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(formatBytes(item.memory))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .help(item.name)
    }

    private func detail(_ item: Cleanup.Item) -> String {
        var parts: [String] = []
        if !item.place.isEmpty { parts.append(item.place) }
        if !item.ports.isEmpty { parts.append("port " + item.ports.joined(separator: ", ")) }
        parts.append("pid \(item.pid)")
        return parts.joined(separator: "  ·  ")
    }

    /// "14:32" today, "Yesterday 09:10", "22 Nov 18:05" before that.
    static func when(_ date: Date, now: Date = Date()) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }
}

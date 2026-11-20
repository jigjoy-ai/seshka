import SwiftUI

struct TabButton: View {
    let title: String
    let icon: String
    let count: Int?
    let selected: Bool
    /// Drawn as its icon alone, and only as wide. For the tabs whose icon needs no word next to it.
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: iconOnly ? 12.5 : 11, weight: .medium))
                if !iconOnly {
                    Text(title).font(.system(size: 11.5, weight: .medium)).fixedSize()
                }
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(selected ? 0.18 : 0.1)))
                }
            }
            .frame(maxWidth: iconOnly ? 40 : .infinity)
            .frame(height: 16)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.accentColor.opacity(0.28) : Color.clear))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(iconOnly ? title : "")
        .accessibilityLabel(title)
    }
}

struct PillButtonStyle: ButtonStyle {
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

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .foregroundStyle(.secondary)
            .contentShape(Circle())
    }
}

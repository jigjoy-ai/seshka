import SwiftUI

/// Shown while seshka keeps the Mac awake for a working session: the lid can be closed now.
struct AwakeSign: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "backpack.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.orange)
            Text("Safe in your backpack. Claude keeps working.")
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // The text keeps its ordinary color, dark on light and light on dark: yellow letters
        // disappear on a light menu.
        .background(Capsule().fill(Palette.yellow.opacity(0.24)))
        .overlay(Capsule().strokeBorder(Palette.yellow.opacity(0.6)))
        .fixedSize()
    }
}

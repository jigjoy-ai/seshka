import SwiftUI

/// Shown while seshka keeps the Mac awake for a working session: the lid can be closed now.
struct AwakeSign: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Yellow letters disappear on a light menu, and a pale yellow sign nearly does. So on a light
        // menu the sign is solid yellow with black on it, and on a dark one it is the other way round.
        let light = scheme == .light
        let ink = Color.black.opacity(0.88)
        HStack(spacing: 6) {
            Image(systemName: "backpack.fill")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(light ? Palette.yellow : ink)
                .frame(width: 18, height: 18)
                .background(Circle().fill(light ? ink : Palette.yellow))
            Text("Safe in your backpack. Claude keeps working.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(light ? ink : Color.primary)
                .lineLimit(1)
        }
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(light ? Palette.yellow : Palette.yellow.opacity(0.2)))
        .overlay(Capsule().strokeBorder(light ? Color.black.opacity(0.1) : Palette.yellow.opacity(0.55)))
        .fixedSize()
    }
}

import SwiftUI

/// What else the team behind seshka makes, and something for the people who use seshka.
struct GiftCard: View {
    @Environment(\.colorScheme) private var scheme

    /// Yellow is the gift's colour, but only shows on a dark menu. On a light one the doll's red does.
    private var accent: Color { scheme == .dark ? Palette.yellow : Palette.red }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "gift.fill").font(.system(size: 13)).foregroundStyle(accent)
                Text("A gift for seshka users").font(.system(size: 12.5, weight: .semibold))
            }
            HStack(alignment: .center, spacing: 10) {
                JigJoyLogo().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JigJoy, from the team behind seshka").font(.system(size: 11.5, weight: .semibold))
                    Text("A debugger for AI agents. Set a breakpoint on any step of a run, change the request, and step on.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("14 days of JigJoy Max, free").font(.system(size: 12, weight: .semibold))
                    Text("No card. Normally $100 a month.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Link(destination: Links.gift) {
                    Text("Claim it")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(scheme == .dark ? Palette.yellow : Color.black.opacity(0.88)))
                        .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointsOnHover()
                .help(Links.gift.absoluteString)
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Text("Also open source:").font(.system(size: 10.5)).foregroundStyle(.secondary)
                project("Mozaik Network", Links.mozaikNetwork)
                project("Baro", Links.baro)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(
                LinearGradient(colors: scheme == .dark ? [Palette.yellow.opacity(0.14), Palette.red.opacity(0.08)]
                                                       : [Palette.yellow.opacity(0.42), Palette.yellow.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(scheme == .dark ? Palette.yellow.opacity(0.35) : Color(red: 0.78, green: 0.52, blue: 0.05).opacity(0.75)))
    }

    private func project(_ name: String, _ address: URL) -> some View {
        Link(destination: address) {
            HStack(spacing: 4) {
                BrandMark(brand: .github).frame(width: 11, height: 11)
                Text(name).font(.system(size: 10.5, weight: .medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .pointsOnHover()
        .help(address.absoluteString)
    }
}

import SwiftUI

/// Where seshka lives outside the menu bar: its code, its site, and who made it.
struct AboutLinks: View {
    var body: some View {
        HStack(spacing: 8) {
            LinkTile(title: "Source code", detail: "Star it on GitHub", address: Links.source) {
                BrandMark(brand: .github)
            }
            LinkTile(title: "seshka.dev", detail: "The website", address: Links.site) {
                Image(systemName: "globe").font(.system(size: 17, weight: .regular))
            }
            LinkTile(title: Links.lotusHandle, detail: "Follow lotus on X", address: Links.lotusOnX) {
                BrandMark(brand: .x).padding(1.5)
            }
        }
    }
}

/// One place to go, as a mark with its name under it.
struct LinkTile<Mark: View>: View {
    let title: String
    let detail: String
    let address: URL
    @ViewBuilder let mark: () -> Mark
    @State private var hovered = false

    var body: some View {
        Link(destination: address) {
            VStack(spacing: 3) {
                mark()
                    .frame(width: 20, height: 20)
                    .padding(.bottom, 3)
                Text(title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovered ? 0.1 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(hovered ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .onHover { hovered = $0 }
        .pointsOnHover()
        .help(address.absoluteString)
    }
}

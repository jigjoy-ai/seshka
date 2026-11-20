import SwiftUI

/// The card as it will be shared, and the ways to take it out of seshka.
struct ShareView: View {
    static let size = CGSize(width: 680, height: 500)
    private static let shrink = 0.5

    let tally: History.Tally
    let period: String
    @State private var png: Data?
    @State private var file: URL?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ShareCard(tally: tally, period: period)
                .scaleEffect(Self.shrink)
                .frame(width: ShareCard.size.width * Self.shrink, height: ShareCard.size.height * Self.shrink)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .padding(.top, 44)
            Text("Only numbers are on it. No project, session or folder names.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .padding(.top, 20)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(copied ? "Copied. Paste it anywhere" : "Copy image") {
                    guard let png else { return }
                    Share.copy(png)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        copied = false
                    }
                }
                .buttonStyle(TourButtonStyle(primary: true))
                Button("Save…") {
                    if let png { Share.save(png) }
                }
                .buttonStyle(TourButtonStyle(primary: false))
                if let file {
                    ShareLink(item: file) { Text("Share…") }
                        .buttonStyle(TourButtonStyle(primary: false))
                }
            }
            .disabled(png == nil)
            .padding(.bottom, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.page)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            png = Share.png(tally, period: period)
            file = png.flatMap(Share.file)
        }
    }
}

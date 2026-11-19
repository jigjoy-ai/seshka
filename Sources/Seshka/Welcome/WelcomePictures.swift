import SwiftUI

/// The right end of a menu bar with seshka's doll in it, open and counting, and the doll itself above.
struct MenuBarPicture: View {
    @State private var open = false

    var body: some View {
        VStack(spacing: 18) {
            Matryoshka(openness: open ? 1 : 0)
                .frame(width: 104, height: 104)
            HStack(spacing: 15) {
                Spacer()
                HStack(spacing: 4) {
                    Image(nsImage: open ? Icon.menuBarOpen : Icon.menuBarClosed)
                        .renderingMode(.template)
                    if open {
                        Text("3").font(.system(size: 13, weight: .medium))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.yellow, lineWidth: 1.5))
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Image(systemName: "magnifyingglass")
                Text("Thu 19 Nov  11:42")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.horizontal, 14)
            .frame(width: 430, height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
        }
        .onAppear {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.55).delay(0.5)) { open = true }
        }
    }
}

struct PictureCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(width: 430, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.line))
            .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

struct Pill: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : Palette.red)
            .background(Capsule().fill(filled ? Palette.red : Palette.red.opacity(0.18)))
    }
}

/// A leftover session as the list shows it, with made-up processes.
struct LeftoverPicture: View {
    private let rows: [(age: String, port: String?, command: String, memory: String)] = [
        ("2d", "3000", "next dev", "812 MB"),
        ("2d", "5173", "vite", "240 MB"),
        ("1d", nil, "Google Chrome for Testing", "356 MB"),
    ]

    var body: some View {
        PictureCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fix the checkout flow").font(.system(size: 12.5, weight: .semibold))
                    Text("shop  ·  3 processes  ·  1.4 GB").font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Pill(text: "Kill 3")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            ForEach(rows, id: \.command) { row in
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(spacing: 8) {
                    Text(row.age)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, alignment: .leading)
                    if let port = row.port {
                        Text(":" + port)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.45, green: 0.68, blue: 1))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.blue.opacity(0.22)))
                    }
                    Text(row.command).font(.system(size: 11.5, design: .monospaced))
                    Spacer()
                    Text(row.memory).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
            }
        }
    }
}

/// Two open sessions as the Sessions tab shows them: one working, one idle for hours.
struct SessionsPicture: View {
    var body: some View {
        VStack(spacing: 8) {
            row(color: .green, title: "Refactor billing", detail: "api  ·  working  ·  open 2h  ·  410 MB", idle: false)
            row(color: .orange, title: "Landing page copy", detail: "website  ·  idle 3h  ·  open 5h  ·  380 MB", idle: true)
        }
    }

    private func row(color: Color, title: String, detail: String, idle: Bool) -> some View {
        PictureCard {
            HStack(spacing: 9) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold))
                    Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if idle { Pill(text: "Kill") }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
    }
}

/// Three things the Disk tab finds, with made-up sizes.
struct DiskPicture: View {
    private let rows: [(title: String, detail: String, size: String, action: String)] = [
        ("agent-a7c65a56", "Worktree  ·  shop  ·  untouched for 4d", "537 MB", "Remove"),
        ("Scratch files", "12 closed sessions", "2.1 GB", "Delete"),
        ("Gradle caches", "Cache", "8.8 GB", "Clear"),
    ]

    var body: some View {
        PictureCard {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 12, weight: .medium))
                        Text(row.detail).font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Text(row.size).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Palette.muted)
                    Pill(text: row.action)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
            }
        }
    }
}

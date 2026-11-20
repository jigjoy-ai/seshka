import SwiftUI

/// The doll's colors, and the dark page they sit on (the same as on seshka.dev).
enum Palette {
    static let red = Color(red: 0xEF / 255, green: 0x4A / 255, blue: 0x3C / 255)
    static let yellow = Color(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x33 / 255)
    static let page = Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
    static let muted = Color(red: 0x9A / 255, green: 0xA0 / 255, blue: 0xA8 / 255)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.1)
}

struct WelcomeView: View {
    static let size = CGSize(width: 640, height: 500)
    static let background = Palette.page

    @EnvironmentObject private var store: Store
    /// Called when the tour ends. True when seshka should open its menu right away.
    let finish: (Bool) -> Void
    @State var page = 0
    @State private var forward = true
    @State private var loginError: String?

    /// One page more on a Mac with a lid: the one about closing it.
    static var pages: Int { Lid.exists ? 6 : 5 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                slide
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
                        removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(backdrop)
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    /// Three soft lights in the doll's colors, as on the website.
    private var backdrop: some View {
        ZStack {
            Palette.page
            RadialGradient(colors: [Palette.red.opacity(0.22), .clear], center: UnitPoint(x: 0.25, y: 0.1), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Palette.yellow.opacity(0.10), .clear], center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Color(red: 0.27, green: 0.43, blue: 0.75).opacity(0.16), .clear], center: UnitPoint(x: 0.6, y: 1.0), startRadius: 0, endRadius: 400)
        }
        .ignoresSafeArea()
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0..<Self.pages, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Palette.yellow : Color.white.opacity(0.22))
                        .frame(width: index == page ? 18 : 6, height: 6)
                }
            }
            .animation(.easeOut(duration: 0.25), value: page)
            Spacer()
            if page > 0 {
                Button("Back") { go(to: page - 1) }
                    .buttonStyle(TourButtonStyle(primary: false))
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            if page < Self.pages - 1 {
                Button("Continue") { go(to: page + 1) }
                    .buttonStyle(TourButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Open seshka") { finish(true) }
                    .buttonStyle(TourButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private func go(to next: Int) {
        forward = next > page
        withAnimation(.easeInOut(duration: 0.3)) { page = next }
    }

    @ViewBuilder
    private var slide: some View {
        switch page {
        case 0:
            Slide(title: "seshka lives in your menu bar",
                  text: "There is no Dock icon and no window to look for. The doll sits at the top of your screen. It opens up when a closed Claude Code session has left something running, and shows how many.") {
                MenuBarPicture()
            }
        case 1:
            Slide(title: "It finds what closed sessions left running",
                  text: "Dev servers, watchers, emulators and browsers outlive the session that started them. seshka lists them by session, with their ports and memory. Kill one, a session's worth, or all of them.") {
                VStack(spacing: 10) {
                    LeftoverPicture()
                    rightNow
                }
            }
        case 2:
            Slide(title: "It watches the sessions that are still open",
                  text: "Every open session, working or idle, and for how long. End an idle one with a click, or let seshka do it after a wait you choose.") {
                VStack(spacing: 10) {
                    SessionsPicture()
                    Toggle(isOn: $store.endsIdleSessions) {
                        Text("End sessions idle for more than \(formatLimit(store.idleLimitMinutes)) automatically")
                            .font(.system(size: 12.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.red)
                }
            }
        case 3:
            Slide(title: "It shows what they left on disk",
                  text: "Worktrees made for agents, scratch files of closed sessions, and caches that fill up again by themselves. See what takes the room and remove it. Nothing goes without a click.") {
                DiskPicture()
            }
        case 4 where Lid.exists:
            Slide(title: "Close the lid. Claude keeps working.",
                  text: "A closed lid puts a Mac to sleep in the middle of a task. With this on, seshka keeps it awake while a session is working, and lets it sleep when the last one finishes. It stops when the battery runs low.") {
                VStack(spacing: 12) {
                    LidPicture()
                    Toggle(isOn: Binding(get: { store.staysAwake }, set: { store.setStaysAwake($0) })) {
                        Text("Keep working with the lid closed").font(.system(size: 12.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.red)
                    Text(store.awakeFailure ?? (Lid.isAllowed ? " " : "It asks for your password once."))
                        .font(.system(size: 11))
                        .foregroundStyle(store.awakeFailure == nil ? Palette.muted : Palette.red)
                }
            }
        default:
            Slide(title: "You are set",
                  text: "seshka looks again every \(store.interval) seconds, and reads only what is already on your Mac. Nothing leaves it.") {
                VStack(spacing: 14) {
                    Matryoshka(openness: 0)
                        .frame(width: 120, height: 120)
                    Toggle(isOn: Binding(
                        get: { store.launchesAtLogin },
                        set: { loginError = store.setLaunchAtLogin($0) }
                    )) {
                        Text("Start seshka when I log in").font(.system(size: 12.5))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.red)
                    if let loginError {
                        Text(loginError).font(.system(size: 11)).foregroundStyle(Palette.red)
                    }
                }
            }
        }
    }

    /// What the first scan found, so the tour is about this Mac and not about an example.
    private var rightNow: some View {
        let count = store.orphanCount
        return HStack(spacing: 7) {
            Circle().fill(Palette.yellow).frame(width: 6, height: 6)
            Group {
                if store.lastScan == nil {
                    Text("Looking at this Mac…")
                } else if count == 0 {
                    Text("On this Mac right now: nothing left running.")
                } else {
                    Text("On this Mac right now: \(count) leftover process\(count == 1 ? "" : "es") holding \(formatBytes(store.orphanMemory)).")
                }
            }
            .font(.system(size: 12.5, weight: .medium))
        }
    }
}

/// One page of the tour: a picture, a title and a few lines.
struct Slide<Picture: View>: View {
    let title: String
    let text: String
    @ViewBuilder let picture: Picture

    var body: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 34)
                .padding(.horizontal, 40)
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(width: 470)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
    }
}

struct TourButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .foregroundStyle(primary ? Palette.page : Color.white)
            .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.1)))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

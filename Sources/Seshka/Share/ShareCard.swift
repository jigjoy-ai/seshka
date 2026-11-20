import SwiftUI

/// The picture that gets shared: what seshka cleaned up over the last week, in numbers.
/// Nothing but numbers goes on it, so it can never show what someone works on.
struct ShareCard: View {
    /// 16:9, the shape X and LinkedIn show without cropping.
    static let size = CGSize(width: 1200, height: 675)

    let tally: History.Tally
    /// "today", "since Tuesday" or "in the last 7 days".
    let period: String

    /// Memory leads. Someone who only cleaned the disk gets the disk as the big number.
    private var leadsWithMemory: Bool { tally.memory > 0 || tally.disk == 0 }

    private var facts: [(String, String)] {
        var facts: [(String, String)] = []
        if tally.processes > 0 { facts.append(("\(tally.processes)", tally.processes == 1 ? "process killed" : "processes killed")) }
        if tally.sessions > 0 { facts.append(("\(tally.sessions)", tally.sessions == 1 ? "session ended" : "sessions ended")) }
        if tally.disk > 0, leadsWithMemory { facts.append((formatBytes(tally.disk), "of disk cleaned")) }
        return facts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Matryoshka(openness: 0).frame(width: 60, height: 60)
                Text("seshka").font(.system(size: 38, weight: .bold))
                Spacer()
            }
            Spacer(minLength: 0)
            // Everything in the middle keeps to the left of the doll, however large the numbers get.
            VStack(alignment: .leading, spacing: 0) {
                Text(formatBytes(leadsWithMemory ? tally.memory : tally.disk))
                    .font(.system(size: 176, weight: .bold, design: .rounded))
                    .tracking(-5)
                Text("\(leadsWithMemory ? "of memory" : "of disk space") freed \(period)")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .padding(.top, -6)
                HStack(spacing: 12) {
                    ForEach(facts, id: \.1) { number, label in
                        HStack(spacing: 8) {
                            Text(number).font(.system(size: 23, weight: .bold, design: .rounded))
                            Text(label).font(.system(size: 22, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                    }
                }
                .padding(.top, 30)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: 800, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Text("Kill what Claude Code left behind.")
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text("seshka.dev").foregroundStyle(Palette.yellow)
            }
            .font(.system(size: 27, weight: .semibold))
        }
        .padding(.horizontal, 68)
        .padding(.vertical, 54)
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(Color.white)
        .background(backdrop)
        .environment(\.colorScheme, .dark)
    }

    /// The soft lights of the website and the tour, with the doll resting in the corner.
    private var backdrop: some View {
        ZStack {
            Palette.page
            RadialGradient(colors: [Palette.red.opacity(0.30), .clear], center: UnitPoint(x: 0.92, y: 0.5), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Palette.yellow.opacity(0.10), .clear], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.27, green: 0.43, blue: 0.75).opacity(0.20), .clear], center: UnitPoint(x: 0.35, y: 1.0), startRadius: 0, endRadius: 620)
            Matryoshka(openness: 0)
                .frame(width: 400, height: 400)
                .position(x: 1012, y: 322)
        }
    }
}

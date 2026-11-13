import SwiftUI

/// The logo, drawn live so it can open and close.
/// `openness` runs from 0 (closed) to 1 (lid off, little doll out) and animates.
/// Shapes, colors and positions mirror design/make-color-icons.py.
struct Matryoshka: View, Animatable {
    var openness: Double

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    private static let red = Color(red: 0xEF / 255, green: 0x4A / 255, blue: 0x3C / 255)
    private static let seam = Color(red: 0xC2 / 255, green: 0x35 / 255, blue: 0x2A / 255)
    private static let yellow = Color(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x33 / 255)
    private static let face = Color(red: 0xFF / 255, green: 0xF4 / 255, blue: 0xE3 / 255)
    private static let ink = Color(red: 0x3A / 255, green: 0x1F / 255, blue: 0x1A / 255)

    // Outlines on a 24x24 grid.
    private static let doll = svgPath("M12 2C14.6 2 16.3 4 16.3 6.4C16.3 8 16.1 9.4 15.7 10.4C17.4 11.4 18.5 13.2 18.7 15.2C18.9 17.6 18.3 20.4 17.2 22L6.8 22C5.7 20.4 5.1 17.6 5.3 15.2C5.5 13.2 6.6 11.4 8.3 10.4C7.9 9.4 7.7 8 7.7 6.4C7.7 4 9.4 2 12 2Z")
    private static let top = svgPath("M12 2C14.6 2 16.3 4 16.3 6.4C16.3 8 16.1 9.4 15.7 10.4C17.4 11.4 18.5 13.1 18.66 14.6L5.34 14.6C5.5 13.1 6.6 11.4 8.3 10.4C7.9 9.4 7.7 8 7.7 6.4C7.7 4 9.4 2 12 2Z")
    private static let bottom = svgPath("M5.3 15.9L18.7 15.9C18.9 17.9 18.3 20.5 17.2 22L6.8 22C5.7 20.5 5.1 17.9 5.3 15.9Z")
    /// The dark strip between the two halves of the closed doll.
    private static let band = svgPath("M5.34 14.6L18.66 14.6L18.7 15.9L5.3 15.9Z")

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 24
            // A bouncy animation overshoots below zero. Clamping turns that into the lid
            // landing, resting, and hopping up once, instead of sinking into the base.
            let t = max(0, CGFloat(openness))
            func mix(_ closed: CGFloat, _ open: CGFloat) -> CGFloat { closed + (open - closed) * t }

            /// Scales a part around `anchor`, turns it around `pivot`, and puts `anchor` at `position`.
            func place(anchor: CGPoint, scale: CGFloat, turn: CGFloat = 0, pivot: CGPoint = .zero, at position: CGPoint) -> CGAffineTransform {
                CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
                    .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                    .concatenating(CGAffineTransform(translationX: -pivot.x, y: -pivot.y))
                    .concatenating(CGAffineTransform(rotationAngle: turn))
                    .concatenating(CGAffineTransform(translationX: pivot.x + position.x, y: pivot.y + position.y))
                    .concatenating(CGAffineTransform(scaleX: unit, y: unit))
            }

            func drawFace(_ transform: CGAffineTransform, eye: CGFloat, in context: GraphicsContext) {
                context.fill(Path(ellipseIn: CGRect(x: 9.4, y: 3.9, width: 5.2, height: 5.2)).applying(transform), with: .color(Self.face))
                for x in [10.9, 13.1] {
                    let rect = CGRect(x: x - eye, y: 6.6 - eye, width: eye * 2, height: eye * 2)
                    context.fill(Path(ellipseIn: rect).applying(transform), with: .color(Self.ink))
                }
            }

            // Closed, the little doll sits hidden behind the big one; open, it stands in the base.
            let kid = place(anchor: CGPoint(x: 12, y: 22), scale: 0.5, at: CGPoint(x: mix(12, 11), y: 21.4))
            let lid = place(anchor: CGPoint(x: 12, y: 14.6), scale: mix(1, 0.78), turn: 24 * .pi / 180 * t,
                            pivot: CGPoint(x: 5.2, y: 0), at: CGPoint(x: mix(12, 11.8), y: mix(14.6, 12.4)))
            let base = place(anchor: CGPoint(x: 12, y: 22), scale: mix(1, 0.8), at: CGPoint(x: 12, y: 22))

            // The little doll is hidden while the lid is nearly down, so it never shows as a
            // sliver through the seam when the lid hops.
            var inside = context
            inside.opacity = Double(max(0, min(1, (t - 0.06) / 0.1)))
            inside.fill(Self.doll.applying(kid), with: .color(Self.yellow))
            drawFace(kid, eye: 0.5, in: inside)

            context.fill(Self.band.applying(base), with: .color(Self.seam.opacity(Double(max(0, min(1, (0.3 - t) / 0.18))))))  // solid while nearly shut, so the little doll never shows through

            context.fill(Self.top.applying(lid), with: .color(Self.red))
            drawFace(lid, eye: mix(0.5, 0.62), in: context)  // eyes widen as the lid comes off

            context.fill(Self.bottom.applying(base), with: .color(Self.red))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Reads the small subset of SVG path syntax the logo uses: absolute M, L, C and Z.
private func svgPath(_ data: String) -> Path {
    var path = Path()
    var command: Character = " "
    var numbers: [CGFloat] = []
    var token = ""

    func endNumber() {
        if let value = Double(token) { numbers.append(CGFloat(value)) }
        token = ""
    }
    func endCommand() {
        endNumber()
        switch command {
        case "M" where numbers.count == 2:
            path.move(to: CGPoint(x: numbers[0], y: numbers[1]))
        case "L" where numbers.count == 2:
            path.addLine(to: CGPoint(x: numbers[0], y: numbers[1]))
        case "C" where numbers.count == 6:
            path.addCurve(to: CGPoint(x: numbers[4], y: numbers[5]),
                          control1: CGPoint(x: numbers[0], y: numbers[1]),
                          control2: CGPoint(x: numbers[2], y: numbers[3]))
        case "Z":
            path.closeSubpath()
        default:
            break
        }
        numbers = []
    }

    for character in data {
        if character.isLetter {
            endCommand()
            command = character
        } else if character == " " || character == "," {
            endNumber()
        } else {
            token.append(character)
        }
    }
    endCommand()
    return path
}

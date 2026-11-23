import SwiftUI

/// The marks of the places seshka links to, drawn from their outlines so they take the text's colour.
struct BrandMark: Shape {
    enum Brand {
        case github
        case x

        /// The outline as an SVG path, on a 24 by 24 grid.
        fileprivate var outline: String {
            switch self {
            case .github:
                return "M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12z"
            case .x:
                return "M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"
            }
        }
    }

    let brand: Brand

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let fit = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: side / 24, y: side / 24)
        return Outline.path(brand.outline).applying(fit)
    }
}

/// Reads the part of the SVG path language these outlines use: moves, lines and curves, no arcs.
enum Outline {
    private static let token = #/[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)/#

    static func path(_ text: String) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"
        var at = CGPoint.zero
        var start = CGPoint.zero
        /// The second control point of the last curve, which a smooth curve mirrors.
        var handle: CGPoint?

        func run() {
            let relative = command.isLowercase
            func point(_ i: Int) -> CGPoint {
                relative ? CGPoint(x: at.x + numbers[i], y: at.y + numbers[i + 1]) : CGPoint(x: numbers[i], y: numbers[i + 1])
            }
            var next: CGPoint?
            switch command.lowercased() {
            case "m":
                at = point(0)
                start = at
                path.move(to: at)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "l":
                at = point(0)
                path.addLine(to: at)
            case "h":
                at.x = relative ? at.x + numbers[0] : numbers[0]
                path.addLine(to: at)
            case "v":
                at.y = relative ? at.y + numbers[0] : numbers[0]
                path.addLine(to: at)
            case "c":
                next = point(2)
                path.addCurve(to: point(4), control1: point(0), control2: point(2))
                at = point(4)
            case "s":
                let mirrored = handle.map { CGPoint(x: 2 * at.x - $0.x, y: 2 * at.y - $0.y) } ?? at
                next = point(0)
                path.addCurve(to: point(2), control1: mirrored, control2: point(0))
                at = point(2)
            default:
                break
            }
            handle = next
            numbers = []
        }

        let needed: [Character: Int] = ["m": 2, "l": 2, "h": 1, "v": 1, "c": 6, "s": 4]
        for match in text.matches(of: token) {
            let piece = String(match.0)
            if let number = Double(piece) {
                numbers.append(CGFloat(number))
                if numbers.count == needed[Character(command.lowercased())] { run() }
            } else if let letter = piece.first {
                if letter == "z" || letter == "Z" {
                    path.closeSubpath()
                    at = start
                    handle = nil
                } else {
                    command = letter
                }
            }
        }
        return path
    }
}

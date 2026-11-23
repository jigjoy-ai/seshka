import Foundation

/// Every address the app points to, in one place.
enum Links {
    static let source = URL(string: "https://github.com/jigjoy-ai/seshka")!
    static let site = URL(string: "https://seshka.dev")!
    static let lotusOnX = URL(string: "https://x.com/lotus_sbc")!
    static let lotusHandle = "@lotus_sbc"
    /// Where a seshka user claims the gift on the About tab. The JigJoy app keeps the code through
    /// signing in and redeems it then: once per account, with no card asked for.
    static let gift = URL(string: "https://app.jigjoy.ai/?redeem=SESHKA&utm_source=seshka&utm_campaign=seshka-gift")!
    static let mozaikNetwork = URL(string: "https://github.com/jigjoy-ai/mozaik-network")!
    static let baro = URL(string: "https://github.com/jigjoy-ai/baro")!
}

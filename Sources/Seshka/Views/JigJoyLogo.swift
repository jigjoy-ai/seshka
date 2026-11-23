import SwiftUI

/// The JigJoy mark on its dark tile, drawn from the logo's own outlines so it stays sharp at any size.
struct JigJoyLogo: View {
    private static let blue = Color(red: 0x78 / 255, green: 0xAA / 255, blue: 0xF6 / 255)
    private static let green = Color(red: 0x90 / 255, green: 0xE8 / 255, blue: 0x6F / 255)
    private static let tile = Color(red: 0x17 / 255, green: 0x18 / 255, blue: 0x1E / 255)

    /// The outlines, on the logo's 500 by 500 grid. The second holds the eyes as holes.
    private static let shapes = Outline.path("M407.8,347.2c-24.1-21.8-56.8-31.6-97.2-29.2-48.2,2.8-57,26.5-57.7,28.5l-.2,.8-.3,.5c-2,4.6-6.1,18.6-.4,27.4,5.9,8.9,20.8,10.6,32.2,10.5,.6,0,1.2,0,1.7,0,39.9,0,61,14.9,71.7,27.4,6.3,7.4,9.8,14.8,11.8,20.4h80.8c-2.8-19-12.2-58.9-42.5-86.3Z M286.1,404.7c-.5,0-1,0-1.5,0-23.7,.2-39.9-6.2-48.4-19.1-11.7-17.9-3-41-1.3-45,2-5.9,15.5-38.1,74.7-41.6,45.8-2.7,83.2,8.8,111.2,34.2,1.2,1.1,2.4,2.2,3.6,3.4-8.2-24.9-17.3-48.7-26-63.5h0c-15.6-29.2-40.3-60.6-78.6-77.9-3.4-19.3-30.4-58.4-30.4-58.4l-37.3,45c-14.6,.2-30.5,2-47.6,6-28.5,6.5-52.2,15.3-71.8,25.8,.9-.6,1.8-1.1,2.7-1.6-15-11.2-64.9-18.2-64.9-18.2l8.5,62.9c-61.9,75.6-22.3,176.9-22.3,176.9H348.8c-6.4-11.9-22.6-28.8-62.8-28.8Zm-26.9-175.6c7.5-1.5,15.2,5,17.1,14.5,1.9,9.5-2.6,18.5-10.1,20-7.5,1.5-15.2-5-17.1-14.5-1.9-9.5,2.6-18.5,10.1-20Zm-73.5,66.6c-7.5,1.5-15.2-5-17.1-14.5-1.9-9.5,2.6-18.5,10.1-20,7.5-1.5,15.2,5,17.1,14.5,1.9,9.5-2.6,18.5-10.1,20Z")
    private static let sparks = Outline.path("M356.7,66.5L340.3,110.6 M427.2,102.9L391,133 M456,180.6L409,183.5")

    var body: some View {
        GeometryReader { box in
            let side = min(box.size.width, box.size.height)
            // The mark sits a little inside the tile, as on JigJoy's own icon.
            let scale = side * 0.8 / 500
            let fit = CGAffineTransform(translationX: side * 0.09, y: side * 0.1).scaledBy(x: scale, y: scale)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(Self.tile)
                Self.shapes.applying(fit).fill(Self.blue)
                Self.sparks.applying(fit).stroke(Self.green, style: StrokeStyle(lineWidth: 17 * scale, lineCap: .round))
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

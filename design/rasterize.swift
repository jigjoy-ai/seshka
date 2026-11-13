import AppKit

// Renders an SVG into the PNG sizes a macOS .iconset needs.
// Usage: swift rasterize.swift <icon.svg> <output.iconset>
let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]) else {
    print("usage: rasterize.swift <icon.svg> <output.iconset>")
    exit(1)
}

func write(pixels: Int, name: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    write(pixels: points, name: "icon_\(points)x\(points).png")
    write(pixels: points * 2, name: "icon_\(points)x\(points)@2x.png")
}

import AppKit

// Renders an SVG to a PNG of the given pixel size.
// Usage: swift svg2png.swift <in.svg> <out.png> <width> <height>
let args = CommandLine.arguments
guard args.count == 5, let w = Int(args[3]), let h = Int(args[4]), let image = NSImage(contentsOfFile: args[1]) else {
    print("usage: svg2png.swift <in.svg> <out.png> <width> <height>")
    exit(1)
}
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))

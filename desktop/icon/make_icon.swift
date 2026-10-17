// Draws the 1024px app icon with CoreGraphics. Usage: make_icon <out.png>
import AppKit

let size = 1024
guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make_icon <out.png>\n".utf8))
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext

// Rounded square with the standard macOS icon inset.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let radius = rect.width * 0.2237
let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Soft shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor(srgbRed: 0.31, green: 0.27, blue: 0.9, alpha: 1).cgColor)
ctx.fillPath()
ctx.restoreGState()

// Gradient #6366f1 -> #4f46e5 (top to bottom)
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let space = CGColorSpaceCreateDeviceRGB()
let colors = [
    NSColor(srgbRed: 0x63 / 255.0, green: 0x66 / 255.0, blue: 0xf1 / 255.0, alpha: 1).cgColor,
    NSColor(srgbRed: 0x4f / 255.0, green: 0x46 / 255.0, blue: 0xe5 / 255.0, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
ctx.restoreGState()

// Letters "JC"
let font = NSFont.systemFont(ofSize: 430, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: -14,
]
let text = NSAttributedString(string: "JC", attributes: attrs)
let ts = text.size()
text.draw(at: NSPoint(x: (CGFloat(size) - ts.width) / 2, y: (CGFloat(size) - ts.height) / 2 + 28))

// Underline accent (an "edit" cursor bar)
let barW: CGFloat = 300
let bar = CGRect(x: (CGFloat(size) - barW) / 2, y: 262, width: barW, height: 28)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 14, cornerHeight: 14, transform: nil))
ctx.fillPath()

NSGraphicsContext.restoreGraphicsState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

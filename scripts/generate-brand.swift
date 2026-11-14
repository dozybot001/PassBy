// Run from the repository root: swift scripts/generate-brand.swift
// App and web icons share the original notebook geometry without a corner badge.
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Bar {
    let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, opacity: CGFloat
}
let bars = [
    Bar(x: 28.25, y: 27, width: 6.5, height: 46, opacity: 1),
    Bar(x: 43.75, y: 33.25, width: 28, height: 6.5, opacity: 1),
    Bar(x: 43.75, y: 46.75, width: 22, height: 6.5, opacity: 1),
    Bar(x: 43.75, y: 60.25, width: 15, height: 6.5, opacity: 0.4),
]
// Option A colors, kraft paper with a vermilion margin (docs/local-notebook.md §7).
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
struct IconColors { let paper: UInt32, margin: UInt32, ink: UInt32 }
let appIcons = [
    ("AppIcon.png", IconColors(paper: 0xF4ECDB, margin: 0xA63F28, ink: 0x2A241C)),
    ("AppIcon-Dark.png", IconColors(paper: 0x1C1915, margin: 0xE58A6E, ink: 0xEFE7D6)),
    ("AppIcon-Tinted.png", IconColors(paper: 0x000000, margin: 0xFFFFFF, ink: 0xD9D9D9)),
]
func draw(_ context: CGContext, appIcon: IconColors? = nil) {
    if let appIcon {
        context.setFillColor(color(appIcon.paper))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    for (index, bar) in bars.enumerated() {
        context.setFillColor(appIcon.map { color(index == 0 ? $0.margin : $0.ink, bar.opacity) } ?? CGColor(gray: 0, alpha: bar.opacity))
        context.addPath(CGPath(roundedRect: CGRect(x: bar.x, y: 100 - bar.y - bar.height,
            width: bar.width, height: bar.height), cornerWidth: 3.25, cornerHeight: 3.25, transform: nil))
        context.fillPath()
    }

}
let asset = URL(fileURLWithPath: "PassBy/Assets.xcassets/BrandMark.imageset", isDirectory: true)
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
let pdfData = NSMutableData()
// Everything but the App Store icon is the bars alone, trimmed to this square as on tenon.asia.
var bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
let pdf = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &bounds, nil)!
pdf.beginPDFPage(nil); pdf.translateBy(x: -22, y: -22); draw(pdf); pdf.endPDFPage(); pdf.closePDF()
try pdfData.write(to: asset.appendingPathComponent("BrandMark.pdf"))
try """
{"images":[{"filename":"BrandMark.pdf","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"preserves-vector-representation":true,"template-rendering-intent":"template"}}
""".write(to: asset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
func writeIcon(_ colors: IconColors, size: Int, to path: String) {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 100, y: CGFloat(size) / 100); draw(context, appIcon: colors)
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))
}
for (name, colors) in appIcons { writeIcon(colors, size: 1024, to: "PassBy/Assets.xcassets/AppIcon.appiconset/\(name)") }
// The website's home-screen icon and share image are the light app icon.
writeIcon(appIcons[0].1, size: 180, to: "public/apple-touch-icon.png")
writeIcon(appIcons[0].1, size: 512, to: "public/web/share.png")
func rects(_ classes: Bool) -> String {
    bars.enumerated().map { index, bar in
        "<rect\(classes ? " class=\"\(index == 0 ? "b" : "l")\"" : "") x=\"\(bar.x)\" y=\"\(bar.y)\" width=\"\(bar.width)\" height=\"\(bar.height)\" rx=\"3.25\" opacity=\"\(bar.opacity)\"/>"
    }.joined()
}
let rectangles = rects(false)
// The favicon follows the system theme: vermilion margin, ink lines.
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="22 22 56 56"><style>.b{fill:#a63f28}.l{fill:#2a241c}@media(prefers-color-scheme:dark){.b{fill:#e58a6e}.l{fill:#efe7d6}}</style>\(rects(true))</svg>
"""
try svg.write(toFile: "public/web/icon.svg", atomically: true, encoding: .utf8)
// Pages inline the mark so it follows the in-app theme, which an <img> cannot.
let symbol = "<svg class=\"product-symbol\" viewBox=\"22 22 56 56\" aria-hidden=\"true\">\(rectangles)</svg>"
for path in ["public/index.html", "public/privacy/index.html", "public/support/index.html", "public/terms/index.html",
             "public/404.html", "public/500.html", "public/maintenance.html"] {
    var page = try String(contentsOfFile: path, encoding: .utf8)
    let start = page.range(of: "<svg class=\"product-symbol\"")!.lowerBound
    page.replaceSubrange(start..<page.range(of: "</svg>", range: start..<page.endIndex)!.upperBound, with: symbol)
    try page.write(toFile: path, atomically: true, encoding: .utf8)
}
print("Generated in-app vector, App Store icons, web icons and inline page marks from one geometry.")

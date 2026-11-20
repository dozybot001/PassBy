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
func draw(_ context: CGContext, appIcon: Bool = false) {
    if appIcon {
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    }
    for bar in bars {
        context.setFillColor(CGColor(gray: 0, alpha: bar.opacity))
        context.addPath(CGPath(roundedRect: CGRect(x: bar.x, y: 100 - bar.y - bar.height,
            width: bar.width, height: bar.height), cornerWidth: 3.25, cornerHeight: 3.25, transform: nil))
        context.fillPath()
    }

}
let asset = URL(fileURLWithPath: "PassBy/Assets.xcassets/BrandMark.imageset", isDirectory: true)
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
let pdfData = NSMutableData()
// Everything but the App Store icon is the bars alone, trimmed to this square.
var bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
let pdf = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &bounds, nil)!
pdf.beginPDFPage(nil); pdf.translateBy(x: -22, y: -22); draw(pdf); pdf.endPDFPage(); pdf.closePDF()
try pdfData.write(to: asset.appendingPathComponent("BrandMark.pdf"))
try """
{"images":[{"filename":"BrandMark.pdf","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"preserves-vector-representation":true,"template-rendering-intent":"template"}}
""".write(to: asset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.scaleBy(x: 10.24, y: 10.24); draw(context, appIcon: true)
let target = URL(fileURLWithPath: "PassBy/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
let rectangles = bars.map { bar in
    "<rect x=\"\(bar.x)\" y=\"\(bar.y)\" width=\"\(bar.width)\" height=\"\(bar.height)\" rx=\"3.25\" opacity=\"\(bar.opacity)\"/>"
}.joined()
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="22 22 56 56"><style>:root{color:#111}@media(prefers-color-scheme:dark){:root{color:#f6f6f6}}</style><g fill="currentColor">\(rectangles)</g></svg>
"""
try svg.write(toFile: "public/web/icon.svg", atomically: true, encoding: .utf8)
// Pages inline the mark so it follows the in-app theme, which an <img> cannot.
let symbol = "<svg class=\"product-symbol\" viewBox=\"22 22 56 56\" aria-hidden=\"true\">\(rectangles)</svg>"
for path in ["public/index.html", "public/privacy/index.html", "public/support/index.html", "public/terms/index.html",
             "public/404.html", "public/500.html"] {
    var page = try String(contentsOfFile: path, encoding: .utf8)
    let start = page.range(of: "<svg class=\"product-symbol\"")!.lowerBound
    page.replaceSubrange(start..<page.range(of: "</svg>", range: start..<page.endIndex)!.upperBound, with: symbol)
    try page.write(toFile: path, atomically: true, encoding: .utf8)
}
print("Generated in-app vector, opaque App Store icon, web mark and inline page marks from one geometry.")

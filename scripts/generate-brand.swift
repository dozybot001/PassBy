// Run from the repository root: swift scripts/generate-brand.swift
// Notebook geometry is retained; the Tenon corner uses the official local asset.
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
    } else {
        context.setFillColor(CGColor(gray: 0, alpha: 0.1))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100),
                               cornerWidth: 22, cornerHeight: 22, transform: nil))
        context.fillPath()
    }
    for bar in bars {
        context.setFillColor(CGColor(gray: 0, alpha: bar.opacity))
        context.addPath(CGPath(roundedRect: CGRect(x: bar.x, y: 100 - bar.y - bar.height,
            width: bar.width, height: bar.height), cornerWidth: 3.25, cornerHeight: 3.25, transform: nil))
        context.fillPath()
    }
    if appIcon {
        let mark = NSImage(contentsOfFile: "PassBy/Assets.xcassets/TenonMark.imageset/TenonMark.png")!
        var source = CGRect(origin: .zero, size: mark.size)
        context.draw(mark.cgImage(forProposedRect: &source, context: nil, hints: nil)!, in: CGRect(x: 62, y: 8, width: 30, height: 30))
    }
}
let asset = URL(fileURLWithPath: "PassBy/Assets.xcassets/BrandMark.imageset", isDirectory: true)
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
let pdfData = NSMutableData()
var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
let pdf = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &bounds, nil)!
pdf.beginPDFPage(nil); draw(pdf); pdf.endPDFPage(); pdf.closePDF()
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
let tenon = try String(contentsOfFile: "public/web/tenon-mark.svg", encoding: .utf8)
    .replacingOccurrences(of: "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\">", with: "<svg x=\"62\" y=\"62\" width=\"30\" height=\"30\" viewBox=\"0 0 64 64\">")
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><style>:root{color:#111}@media(prefers-color-scheme:dark){:root{color:#f6f6f6}}</style><g fill="currentColor"><rect width="100" height="100" rx="22" opacity=".1"/>\(rectangles)</g>\(tenon)</svg>
"""
try svg.write(toFile: "public/web/icon.svg", atomically: true, encoding: .utf8)
print("Generated in-app vector, opaque App Store icon and web mark from one geometry.")

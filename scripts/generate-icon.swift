#!/usr/bin/env swift
// Generates Galley's app icon: a typeset page on Thesis paper.
// Usage: swift scripts/generate-icon.swift <output-appiconset-dir>

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count == 2 else {
    print("usage: generate-icon.swift <AppIcon.appiconset dir>")
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let cream = color(0xF6F2E9)
let creamLo = color(0xEDE7D9)
let ink = color(0x15140E)
let inkSoft = color(0x4A4639)
let mutedBar = color(0x8E8879, 0.55)
let spectral: [(UInt32, CGFloat)] = [
    (0xFF5D73, 0.0), (0xFFB454, 0.25), (0x36D6C3, 0.5), (0x6AA6FF, 0.75), (0xB07BFF, 1.0),
]

func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(size: CGFloat) -> CGImage? {
    let s = size / 1024.0
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS icon canvas: 1024 with the visible squircle ~832 centered.
    let plate = CGRect(x: 96 * s, y: 96 * s, width: 832 * s, height: 832 * s)
    let plateRadius = 186 * s

    // soft drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14 * s),
        blur: 36 * s,
        color: color(0x241C0C, 0.38)
    )
    ctx.addPath(roundedRect(ctx, plate, radius: plateRadius))
    ctx.setFillColor(cream)
    ctx.fillPath()
    ctx.restoreGState()

    // paper gradient
    ctx.saveGState()
    ctx.addPath(roundedRect(ctx, plate, radius: plateRadius))
    ctx.clip()
    let paperGrad = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(0xFAF7F0), cream, creamLo] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        paperGrad,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )

    // hairline inner border
    ctx.addPath(roundedRect(ctx, plate.insetBy(dx: 3 * s, dy: 3 * s), radius: plateRadius - 3 * s))
    ctx.setStrokeColor(color(0xC3BCAC, 0.7))
    ctx.setLineWidth(2.5 * s)
    ctx.strokePath()

    // ---- typeset block, centered ----
    // In CG coordinates the origin is bottom-left; lay out top-down.
    let blockLeft = 268 * s
    let barRadius = 22 * s

    func bar(_ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ fill: CGColor) {
        let rect = CGRect(x: blockLeft, y: y * s, width: width * s, height: height * s)
        ctx.addPath(roundedRect(ctx, rect, radius: min(barRadius, rect.height / 2)))
        ctx.setFillColor(fill)
        ctx.fillPath()
    }

    // title bar (the headline)
    bar(658, 340, 74, ink)

    // spectral proof line — the signature
    let specRect = CGRect(x: blockLeft, y: 588 * s, width: 216 * s, height: 22 * s)
    ctx.saveGState()
    ctx.addPath(roundedRect(ctx, specRect, radius: 11 * s))
    ctx.clip()
    let specGrad = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: spectral.map { color($0.0) } as CFArray,
        locations: spectral.map { $0.1 }
    )!
    ctx.drawLinearGradient(
        specGrad,
        start: CGPoint(x: specRect.minX, y: specRect.midY),
        end: CGPoint(x: specRect.maxX, y: specRect.midY),
        options: []
    )
    ctx.restoreGState()

    // body text lines
    bar(480, 488, 40, inkSoft)
    bar(400, 452, 40, inkSoft)
    bar(320, 488, 40, inkSoft)
    bar(240, 336, 40, mutedBar)

    ctx.restoreGState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

let specs: [(name: String, points: Int, scale: Int)] = [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2),
]

for spec in specs {
    let px = CGFloat(spec.points * spec.scale)
    if let img = draw(size: px) {
        writePNG(img, to: outDir.appendingPathComponent("\(spec.name).png"))
    }
}

let contents: [String: Any] = [
    "images": specs.map { spec in
        [
            "filename": "\(spec.name).png",
            "idiom": "mac",
            "scale": "\(spec.scale)x",
            "size": "\(spec.points)x\(spec.points)",
        ]
    },
    "info": ["author": "xcode", "version": 1],
]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outDir.appendingPathComponent("Contents.json"))
print("✓ icon written to \(outDir.path)")

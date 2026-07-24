#!/usr/bin/env swift
// Offscreen screenshot pipeline for Galley's launch marketing images.
// Drives the app's real WKWebView renderer (template.html + reader.bundle.js)
// in a window positioned far off any physical screen — nothing appears on
// the user's display and nothing steals focus. Also does small pixel
// compositing jobs (theme-grid strip stacking, Product Hunt cream frames)
// with CoreGraphics so the whole pipeline lives in one file.
//
// Usage: swift scripts/snapshot.swift <config.json>
//
// config.json is either a single job object or an array of job objects.
// Job "type" values: "render" (load a markdown file through Reader and
// snapshot it), "html" (load an arbitrary local HTML file and snapshot it),
// "hstack" (stitch N same-height images side by side with hairlines),
// "frame" (place one image on a cream canvas with margin + hairline +
// rounded corners).

import AppKit
import WebKit
import Foundation

// MARK: - CLI

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: snapshot.swift <config.json>\n".data(using: .utf8)!)
    exit(1)
}
let configURL = URL(fileURLWithPath: args[1])

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("snapshot.swift: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

guard let configData = try? Data(contentsOf: configURL) else {
    fail("could not read config at \(configURL.path)")
}
guard let parsed = try? JSONSerialization.jsonObject(with: configData) else {
    fail("could not parse JSON in \(configURL.path)")
}
let jobs: [[String: Any]]
if let arr = parsed as? [[String: Any]] {
    jobs = arr
} else if let obj = parsed as? [String: Any] {
    jobs = [obj]
} else {
    fail("config must be an object or array of objects")
}

// MARK: - App setup (headless, no dock icon, cannot become active)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.finishLaunching()

// Offscreen windows still report a backing scale factor (inherited from the
// main screen); size the WKWebView in points so that, rendered at this
// scale, it lands on exact target pixel sizes.
//
// This used to read NSScreen.main?.backingScaleFactor, which is whatever
// display happens to be "main" in the calling process's session — that
// varies across invocations (e.g. an attached external non-Retina display)
// and silently changed the point-size viewport all the layouts were
// authored against, producing correctly-pixel-sized but wrongly-laid-out
// images. Every existing asset in docs/launch was authored assuming 2x
// (LAUNCH.md: "1440x900 points on the 2x display gives 2880x1800 native
// pixels"), so hardcode it for determinism instead of trusting the
// environment.
let backingScale: CGFloat = 2.0
print("using fixed backingScaleFactor: \(backingScale)")

// MARK: - Theme data (transcribed verbatim from Galley/Core/Themes.swift)

struct Palette {
    let bg, bgHi, bgDeep, ink, ink2, ink3, muted, line, lineStrong: String
    let accent, live: String
    let synRed, synAmber, synTeal, synBlue, synPurple, synComment: String
    var json: [String: Any] {
        [
            "bg": bg, "bgHi": bgHi, "bgDeep": bgDeep, "ink": ink, "ink2": ink2, "ink3": ink3,
            "muted": muted, "line": line, "lineStrong": lineStrong, "accent": accent, "live": live,
            "synRed": synRed, "synAmber": synAmber, "synTeal": synTeal, "synBlue": synBlue,
            "synPurple": synPurple, "synComment": synComment,
        ]
    }
}

let fontCSS: [String: String] = [
    "fraunces": "\"Fraunces Variable\", ui-serif, Georgia, serif",
    "bricolage": "\"Bricolage Grotesque Variable\", ui-rounded, system-ui, sans-serif",
    "inter": "\"Inter Variable\", system-ui, -apple-system, sans-serif",
    "newYork": "ui-serif, \"New York\", Georgia, serif",
    "system": "system-ui, -apple-system, sans-serif",
    "jetbrainsMono": "\"JetBrains Mono Variable\", ui-monospace, \"SF Mono\", monospace",
    "sfMono": "ui-monospace, \"SF Mono\", monospace",
]

struct Theme {
    let id: String
    let light: Palette
    let dark: Palette
    let displayFont: String
    let bodyFont: String
    let monoFont: String
    let headingWeight: Int
    let spectral: Bool
}

let themes: [String: Theme] = [
    "thesis": Theme(
        id: "thesis",
        light: Palette(
            bg: "#F1ECE2", bgHi: "#F8F5EE", bgDeep: "#EAE4D6",
            ink: "#15140E", ink2: "#4A4639", ink3: "#403C31", muted: "#8E8879",
            line: "#D9D3C6", lineStrong: "#C3BCAC",
            accent: "#3A6CC9", live: "#1F8A7D",
            synRed: "#C04A5E", synAmber: "#9C6A1F", synTeal: "#177A6E",
            synBlue: "#3A6CC9", synPurple: "#7A51C7", synComment: "#8E8879"
        ),
        dark: Palette(
            bg: "#17160F", bgHi: "#1E1D14", bgDeep: "#121109",
            ink: "#ECE7DA", ink2: "#C9C3B2", ink3: "#B5AF9E", muted: "#8E8879",
            line: "#353327", lineStrong: "#4A473A",
            accent: "#8FBCFF", live: "#36D6C3",
            synRed: "#FF8A9A", synAmber: "#FFC37A", synTeal: "#5DE3D0",
            synBlue: "#8FBCFF", synPurple: "#C9A2FF", synComment: "#7D7869"
        ),
        displayFont: "fraunces", bodyFont: "inter", monoFont: "jetbrainsMono",
        headingWeight: 600, spectral: true
    ),
    "manuscript": Theme(
        id: "manuscript",
        light: Palette(
            bg: "#F9F5EC", bgHi: "#FFFDF8", bgDeep: "#F0EADC",
            ink: "#221E17", ink2: "#5A4F41", ink3: "#4A4136", muted: "#93887A",
            line: "#E2DACB", lineStrong: "#CFC5B2",
            accent: "#A33B2E", live: "#4A7A62",
            synRed: "#B0503F", synAmber: "#96702B", synTeal: "#4A7A62",
            synBlue: "#4E6FA3", synPurple: "#7A5E93", synComment: "#93887A"
        ),
        dark: Palette(
            bg: "#201B14", bgHi: "#282219", bgDeep: "#17130D",
            ink: "#EDE4D3", ink2: "#C9BDA6", ink3: "#B4A78F", muted: "#8F8672",
            line: "#3A342A", lineStrong: "#4E463A",
            accent: "#E08D7D", live: "#7FBF9E",
            synRed: "#E08D7D", synAmber: "#D9B36B", synTeal: "#8FCDA9",
            synBlue: "#92AEDC", synPurple: "#B79ED6", synComment: "#8F8672"
        ),
        displayFont: "newYork", bodyFont: "newYork", monoFont: "jetbrainsMono",
        headingWeight: 650, spectral: false
    ),
    "studio": Theme(
        id: "studio",
        light: Palette(
            bg: "#FFFFFF", bgHi: "#F6F7F8", bgDeep: "#EEF0F2",
            ink: "#17181A", ink2: "#45484D", ink3: "#3A3D42", muted: "#8A8F98",
            line: "#E4E6EA", lineStrong: "#CBCFD6",
            accent: "#3B72E8", live: "#12A594",
            synRed: "#D0435B", synAmber: "#B0730C", synTeal: "#0E8A74",
            synBlue: "#2F6BDF", synPurple: "#7A4FD0", synComment: "#8A8F98"
        ),
        dark: Palette(
            bg: "#131417", bgHi: "#1B1D21", bgDeep: "#0D0E10",
            ink: "#E8EAED", ink2: "#B5BAC3", ink3: "#9BA1AB", muted: "#7E838C",
            line: "#2A2D33", lineStrong: "#3D4149",
            accent: "#7AA5FF", live: "#4ADFC4",
            synRed: "#FF7B93", synAmber: "#FFC069", synTeal: "#4ADFC4",
            synBlue: "#82AFFF", synPurple: "#BB9AF7", synComment: "#7E838C"
        ),
        displayFont: "system", bodyFont: "system", monoFont: "sfMono",
        headingWeight: 700, spectral: false
    ),
    "terminal": Theme(
        id: "terminal",
        light: Palette(
            bg: "#F4F4F0", bgHi: "#FBFBF8", bgDeep: "#E9E9E2",
            ink: "#1A1D1A", ink2: "#46504A", ink3: "#3B443E", muted: "#7E877F",
            line: "#DBDBD2", lineStrong: "#C2C4B8",
            accent: "#157F5B", live: "#157F5B",
            synRed: "#C25450", synAmber: "#9A7420", synTeal: "#157F5B",
            synBlue: "#3B6FB4", synPurple: "#8455B7", synComment: "#7E877F"
        ),
        dark: Palette(
            bg: "#0D120E", bgHi: "#141B16", bgDeep: "#080C09",
            ink: "#D6E5D8", ink2: "#A3B8A7", ink3: "#8CA391", muted: "#6F8273",
            line: "#243026", lineStrong: "#35453A",
            accent: "#48E5A3", live: "#48E5A3",
            synRed: "#FF7E79", synAmber: "#E5C07B", synTeal: "#56D6AD",
            synBlue: "#61AFEF", synPurple: "#C678DD", synComment: "#6F8273"
        ),
        displayFont: "jetbrainsMono", bodyFont: "jetbrainsMono", monoFont: "jetbrainsMono",
        headingWeight: 700, spectral: false
    ),
    "editorial": Theme(
        id: "editorial",
        light: Palette(
            bg: "#FFFEFB", bgHi: "#F7F5F0", bgDeep: "#EFEBE3",
            ink: "#0E0D0B", ink2: "#3E3B36", ink3: "#33302B", muted: "#8C877E",
            line: "#E6E2D9", lineStrong: "#CDC7BA",
            accent: "#E23B2E", live: "#12A594",
            synRed: "#C93A32", synAmber: "#A06B14", synTeal: "#0F8A74",
            synBlue: "#2F62C4", synPurple: "#7648C8", synComment: "#8C877E"
        ),
        dark: Palette(
            bg: "#151412", bgHi: "#1D1C19", bgDeep: "#0E0D0B",
            ink: "#F2EFE9", ink2: "#C6C1B7", ink3: "#B0AA9E", muted: "#8C877E",
            line: "#34322D", lineStrong: "#48453F",
            accent: "#FF6A5C", live: "#4ADFC4",
            synRed: "#FF7B71", synAmber: "#E8B45B", synTeal: "#43D1B4",
            synBlue: "#7FA9F5", synPurple: "#BB97F0", synComment: "#8C877E"
        ),
        displayFont: "bricolage", bodyFont: "inter", monoFont: "jetbrainsMono",
        headingWeight: 760, spectral: false
    ),
]

// MARK: - JSON helpers

func jsonString(_ obj: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
          var s = String(data: data, encoding: .utf8) else { return "null" }
    s = s.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
    s = s.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return s
}

func hexColor(_ hex: String) -> CGColor {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return CGColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1
    )
}

// MARK: - PNG writing

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    return (try? data.write(to: url)) != nil
}

// MARK: - Render / HTML jobs (WKWebView)

/// Runs one WKWebView-backed job to completion, synchronously (pumps the
/// run loop internally), then calls `done`. Shared by "render" and "html".
final class WebJobRunner: NSObject, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    var onLoad: (() -> Void)?

    init(pixelWidth: Int, pixelHeight: Int) {
        // CSS viewport is sized in points, matching what a real 2x Retina
        // window would present; the eventual snapshot is asked for the
        // exact target pixel width regardless of this offscreen window's
        // actual backing scale factor, via WKSnapshotConfiguration.
        let pointSize = NSSize(width: CGFloat(pixelWidth) / backingScale, height: CGFloat(pixelHeight) / backingScale)
        let rect = NSRect(x: -20000, y: -20000, width: pointSize.width, height: pointSize.height)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrame(rect, display: false)
        webView = WKWebView(frame: NSRect(origin: .zero, size: pointSize), configuration: config)
        webView.allowsMagnification = false
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFront(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoad?()
    }

    func loadFile(_ url: URL, readAccess: URL) {
        webView.loadFileURL(url, allowingReadAccessTo: readAccess)
    }
}

/// Blocks (by pumping RunLoop.main) until `predicate` returns a non-nil
/// value or `timeout` elapses, then returns that value (or nil on timeout).
@discardableResult
func pump<T>(timeout: TimeInterval, interval: TimeInterval = 0.05, _ predicate: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let v = predicate() { return v }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(interval))
    }
    return predicate()
}

func evalJS(_ webView: WKWebView, _ script: String) -> Any? {
    var result: Any?
    var finished = false
    webView.evaluateJavaScript(script) { value, _ in
        result = value
        finished = true
    }
    pump(timeout: 10) { finished ? true : nil }
    return result
}

func snapshotPNG(_ webView: WKWebView, pixelWidth: Int, pixelHeight: Int, to path: String) {
    let cfg = WKSnapshotConfiguration()
    cfg.rect = webView.bounds
    // Explicit snapshotWidth, not left nil: nil defers to the actual window's
    // backing scale factor, which depends on whatever screen happens to be
    // "main" in the calling session (varies run to run — an attached
    // non-Retina external display makes it 1, silently halving output
    // dimensions relative to the assumed-2x point-size layout). Pinning it
    // to the exact target pixel width makes the output deterministic
    // regardless of the environment; height follows from the aspect ratio,
    // which already matches by construction (WebJobRunner's point-size is
    // pixelWidth/backingScale x pixelHeight/backingScale).
    cfg.snapshotWidth = NSNumber(value: pixelWidth)
    var image: NSImage?
    var finished = false
    var errText: String?
    webView.takeSnapshot(with: cfg) { img, err in
        image = img
        errText = err?.localizedDescription
        finished = true
    }
    pump(timeout: 20) { finished ? true : nil }
    guard let image else {
        fail("snapshot failed for \(path): \(errText ?? "unknown error")")
    }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("could not extract CGImage for \(path)")
    }
    guard writePNG(cgImage, to: path) else {
        fail("could not write PNG to \(path)")
    }
    if cgImage.width != pixelWidth || cgImage.height != pixelHeight {
        print("WARNING: \(path) is \(cgImage.width)x\(cgImage.height), expected \(pixelWidth)x\(pixelHeight)")
    } else {
        print("wrote \(path) (\(cgImage.width)x\(cgImage.height))")
    }
}

func waitForFonts(_ webView: WKWebView, timeout: TimeInterval = 6) {
    pump(timeout: timeout) {
        (evalJS(webView, "document.fonts.status") as? String) == "loaded" ? true : nil
    }
}

func waitForMermaid(_ webView: WKWebView, timeout: TimeInterval = 6) {
    pump(timeout: timeout) {
        (evalJS(webView, "document.querySelectorAll('.mermaid-block svg').length > 0") as? Bool) == true ? true : nil
    }
}

func runRenderJob(_ job: [String: Any]) {
    guard let webDirPath = job["webDir"] as? String,
          let markdownPath = job["markdownFile"] as? String,
          let themeID = job["theme"] as? String,
          let variant = job["variant"] as? String,
          let pixelWidth = job["pixelWidth"] as? Int,
          let pixelHeight = job["pixelHeight"] as? Int,
          let output = job["output"] as? String
    else { fail("render job missing required fields: \(job)") }

    guard let theme = themes[themeID] else { fail("unknown theme id \(themeID)") }
    guard let markdown = try? String(contentsOfFile: markdownPath, encoding: .utf8) else {
        fail("could not read markdown at \(markdownPath)")
    }

    let isDark = variant == "dark"
    let palette = isDark ? theme.dark : theme.light
    let scrollFraction = job["scrollFraction"] as? Double ?? 0
    let waitSeconds = job["waitSeconds"] as? Double ?? 1.2
    let wantMermaid = job["waitForMermaid"] as? Bool ?? false

    let runner = WebJobRunner(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    var loaded = false
    runner.onLoad = { loaded = true }
    let webDir = URL(fileURLWithPath: webDirPath, isDirectory: true)
    let templateURL = webDir.appendingPathComponent("template.html")
    runner.loadFile(templateURL, readAccess: webDir)
    pump(timeout: 15) { loaded ? true : nil }

    pump(timeout: 10) {
        (evalJS(runner.webView, "typeof Reader") as? String) == "object" ? true : nil
    }

    let options: [String: Any] = [
        "mode": isDark ? "dark" : "light",
        "palette": palette.json,
        "fonts": [
            "display": fontCSS[theme.displayFont] ?? "",
            "body": fontCSS[theme.bodyFont] ?? "",
            "mono": fontCSS[theme.monoFont] ?? "",
        ],
        "headingWeight": theme.headingWeight,
        "spectral": theme.spectral,
        "measure": job["measure"] as? Int ?? 70,
        "scale": job["scale"] as? Double ?? 1.0,
        "allowRemote": false,
        "presenting": false,
    ]
    _ = evalJS(runner.webView, "Reader.applyOptions(\(jsonString(options)))")

    let load: [String: Any] = [
        "markdown": markdown,
        "docDir": NSNull(),
        "isReload": false,
        "followTail": false,
        "showFrontMatter": true,
        "typographer": true,
    ]
    _ = evalJS(runner.webView, "Reader.load(\(jsonString(load)))")

    if scrollFraction > 0 {
        pump(timeout: 2, interval: 0.1) { nil as Bool? } // let first layout settle
        _ = evalJS(runner.webView, "Reader.setScrollFraction(\(scrollFraction))")
    }

    waitForFonts(runner.webView)
    if wantMermaid { waitForMermaid(runner.webView) }
    pump(timeout: waitSeconds, interval: waitSeconds) { nil as Bool? }

    snapshotPNG(runner.webView, pixelWidth: pixelWidth, pixelHeight: pixelHeight, to: output)
    runner.window.orderOut(nil)
}

func runHTMLJob(_ job: [String: Any]) {
    guard let htmlPath = job["htmlFile"] as? String,
          let pixelWidth = job["pixelWidth"] as? Int,
          let pixelHeight = job["pixelHeight"] as? Int,
          let output = job["output"] as? String
    else { fail("html job missing required fields: \(job)") }

    let waitSeconds = job["waitSeconds"] as? Double ?? 1.0
    let runner = WebJobRunner(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    var loaded = false
    runner.onLoad = { loaded = true }
    let htmlURL = URL(fileURLWithPath: htmlPath)
    runner.loadFile(htmlURL, readAccess: htmlURL.deletingLastPathComponent())
    pump(timeout: 15) { loaded ? true : nil }

    waitForFonts(runner.webView)
    pump(timeout: waitSeconds, interval: waitSeconds) { nil as Bool? }

    snapshotPNG(runner.webView, pixelWidth: pixelWidth, pixelHeight: pixelHeight, to: output)
    runner.window.orderOut(nil)
}

// MARK: - Compositing jobs (CoreGraphics, no WebView)

func loadCGImage(_ path: String) -> CGImage {
    guard let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { fail("could not load image at \(path)") }
    return cg
}

func runHStackJob(_ job: [String: Any]) {
    guard let images = job["images"] as? [String],
          let pixelWidth = job["pixelWidth"] as? Int,
          let pixelHeight = job["pixelHeight"] as? Int,
          let output = job["output"] as? String
    else { fail("hstack job missing required fields: \(job)") }
    let hairlineColor = hexColor(job["hairlineColor"] as? String ?? "#C3BCAC")

    guard let ctx = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("could not create bitmap context for \(output)") }

    let n = images.count
    let stripW = pixelWidth / n
    var xs: [Int] = []
    for (i, path) in images.enumerated() {
        let cg = loadCGImage(path)
        let x = i * stripW
        xs.append(x)
        // Draw each strip at its native pixel size, anchored top-left, in a
        // flipped coordinate system (CGContext origin is bottom-left).
        let drawRect = CGRect(x: x, y: pixelHeight - cg.height, width: cg.width, height: cg.height)
        ctx.draw(cg, in: drawRect)
    }
    // Hairlines overlaid at internal strip boundaries (canvas width stays exact).
    ctx.setFillColor(hairlineColor)
    for i in 1..<n {
        ctx.fill(CGRect(x: xs[i], y: 0, width: 1, height: pixelHeight))
    }
    guard let image = ctx.makeImage() else { fail("could not render composite for \(output)") }
    guard writePNG(image, to: output) else { fail("could not write PNG to \(output)") }
    print("wrote \(output) (\(image.width)x\(image.height))")
}

func runFrameJob(_ job: [String: Any]) {
    guard let sourcePath = job["source"] as? String,
          let pixelWidth = job["pixelWidth"] as? Int,
          let pixelHeight = job["pixelHeight"] as? Int,
          let output = job["output"] as? String
    else { fail("frame job missing required fields: \(job)") }
    let margin = CGFloat(job["margin"] as? Double ?? 40)
    let cornerRadius = CGFloat(job["cornerRadius"] as? Double ?? 10)
    let borderWidth = CGFloat(job["borderWidth"] as? Double ?? 1)
    let borderColor = hexColor(job["borderColor"] as? String ?? "#D9D3C6")
    let bgColor = hexColor(job["bgColor"] as? String ?? "#F1ECE2")

    let source = loadCGImage(sourcePath)
    guard let ctx = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("could not create bitmap context for \(output)") }

    ctx.setFillColor(bgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

    let boxW = CGFloat(pixelWidth) - margin * 2
    let boxH = CGFloat(pixelHeight) - margin * 2
    let srcAspect = CGFloat(source.width) / CGFloat(source.height)
    let boxAspect = boxW / boxH
    var drawW = boxW
    var drawH = boxH
    if srcAspect > boxAspect {
        drawH = boxW / srcAspect
    } else {
        drawW = boxH * srcAspect
    }
    let drawX = (CGFloat(pixelWidth) - drawW) / 2
    let drawY = (CGFloat(pixelHeight) - drawH) / 2
    let rect = CGRect(x: drawX, y: drawY, width: drawW, height: drawH)

    ctx.saveGState()
    let clipPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()
    ctx.draw(source, in: rect)
    ctx.restoreGState()

    ctx.setStrokeColor(borderColor)
    ctx.setLineWidth(borderWidth)
    let strokeRect = rect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
    let strokePath = CGPath(roundedRect: strokeRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(strokePath)
    ctx.strokePath()

    guard let image = ctx.makeImage() else { fail("could not render frame for \(output)") }
    guard writePNG(image, to: output) else { fail("could not write PNG to \(output)") }
    print("wrote \(output) (\(image.width)x\(image.height))")
}

// MARK: - Dispatch

for job in jobs {
    guard let type = job["type"] as? String else { fail("job missing \"type\": \(job)") }
    switch type {
    case "render":
        runRenderJob(job)
    case "html":
        runHTMLJob(job)
    case "hstack":
        runHStackJob(job)
    case "frame":
        runFrameJob(job)
    default:
        fail("unknown job type \(type)")
    }
}

exit(0)

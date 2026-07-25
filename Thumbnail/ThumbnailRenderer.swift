// ThumbnailRenderer.swift
// Pure-AppKit renderer for Galley's Finder thumbnails: skims a Markdown file
// into a tiny structural outline and draws it as a miniature typeset page.
// Deliberately has NO QuickLook imports so it can be compiled standalone by
// scripts/render-thumb-harness.swift.

import AppKit
import Foundation

struct MarkdownSkim {
    enum Block {
        case body(String)
        case heading(String)
        case bullet(String)
        case mono([String])
    }

    var title: String
    var blocks: [Block]
}

enum ThumbnailRenderer {

    // MARK: - Skimming

    static func skim(data: Data, filename: String) -> MarkdownSkim {
        // Cap BEFORE decoding: thumbnails never need more than the head.
        let capped = data.prefix(65536)
        var text: String
        if let strict = String(data: capped, encoding: .utf8) {
            text = strict
        } else {
            // Only treat the data as UTF-16 when it actually starts with a
            // UTF-16 BOM. Blindly retrying .utf16 on a UTF-8 head whose cap
            // cut a multibyte character SUCCEEDS on the even-length prefix
            // and renders the whole thumbnail as CJK mojibake.
            let bom = [UInt8](capped.prefix(2))
            if bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF],
               let utf16 = String(data: capped, encoding: .utf16) {
                text = utf16
            } else {
                // The 64KB cap can slice a multibyte UTF-8 sequence: drop up
                // to 3 trailing bytes of the incomplete sequence and retry a
                // strict decode before falling back to lossy replacement.
                var retried: String?
                var trimmed = capped
                for _ in 0..<3 {
                    guard !trimmed.isEmpty else { break }
                    trimmed = trimmed.dropLast()
                    if let s = String(data: trimmed, encoding: .utf8) {
                        retried = s
                        break
                    }
                }
                text = retried ?? String(decoding: capped, as: UTF8.self)
            }
        }

        // Strip BOM.
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }

        // Drop YAML front matter.
        if let re = try? NSRegularExpression(
            pattern: "^---[ \\t]*\\r?\\n[\\s\\S]*?\\r?\\n---[ \\t]*\\r?(\\n|$)"
        ) {
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
               m.range.location == 0 {
                text = ns.substring(from: m.range.length)
            }
        }

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = text.components(separatedBy: "\n")

        let fallbackTitle = (filename as NSString).deletingPathExtension

        // Title: first ATX "# " heading within the first 40 non-empty lines,
        // else first setext heading (line followed by ===), else filename.
        var title = ""
        var titleLineIndex = -1   // index of the title's source line
        var titleConsumesNext = false  // setext: the === line too
        var nonEmptySeen = 0
        var setextCandidate: (index: Int, text: String)?

        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            nonEmptySeen += 1
            if nonEmptySeen > 40 { break }

            if line.hasPrefix("# ") {
                title = cleanInline(String(line.dropFirst(2)))
                titleLineIndex = i
                break
            }
            if setextCandidate == nil,
               !line.hasPrefix("#"),
               !line.hasPrefix("```"),
               i + 1 < lines.count {
                let next = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !next.isEmpty, next.allSatisfy({ $0 == "=" }) {
                    setextCandidate = (i, cleanInline(line))
                }
            }
        }
        if title.isEmpty, let setext = setextCandidate {
            title = setext.text
            titleLineIndex = setext.index
            titleConsumesNext = true
        }
        if title.isEmpty {
            title = fallbackTitle
        }

        // Blocks: scan up to ~80 further lines into at most 24 blocks.
        var blocks: [MarkdownSkim.Block] = []
        var paragraph: [String] = []
        var inFence = false
        var fenceLines: [String] = []
        var scanned = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                let joined = cleanInline(paragraph.joined(separator: " "))
                if !joined.isEmpty {
                    blocks.append(.body(joined))
                }
                paragraph = []
            }
        }
        func flushFence() {
            // Leading/trailing blank fence lines render as empty rows inside
            // the code chip, making its vertical padding look asymmetric.
            while let last = fenceLines.last,
                  last.trimmingCharacters(in: .whitespaces).isEmpty {
                fenceLines.removeLast()
            }
            while let first = fenceLines.first,
                  first.trimmingCharacters(in: .whitespaces).isEmpty {
                fenceLines.removeFirst()
            }
            if !fenceLines.isEmpty {
                blocks.append(.mono(fenceLines))
            }
            fenceLines = []
        }

        var startIndex = 0
        if titleLineIndex >= 0 {
            startIndex = titleLineIndex + (titleConsumesNext ? 2 : 1)
        }

        for raw in lines.dropFirst(startIndex) {
            if scanned >= 80 || blocks.count >= 24 { break }
            scanned += 1

            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inFence {
                    inFence = false
                    flushFence()
                } else {
                    flushParagraph()
                    inFence = true
                }
                continue
            }
            if inFence {
                if fenceLines.count < 6 {
                    fenceLines.append(String(raw.prefix(120)))
                }
                continue
            }

            if line.isEmpty {
                flushParagraph()
                continue
            }

            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" })
                if hashes.count <= 6 {
                    let rest = line.dropFirst(hashes.count)
                    if rest.hasPrefix(" ") || rest.isEmpty {
                        flushParagraph()
                        let cleaned = cleanInline(String(rest))
                        if !cleaned.isEmpty {
                            blocks.append(.heading(cleaned))
                        }
                        continue
                    }
                }
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                let cleaned = cleanInline(String(line.dropFirst(2)))
                if !cleaned.isEmpty {
                    blocks.append(.bullet(cleaned))
                }
                continue
            }
            if let dotIndex = line.firstIndex(of: "."),
               dotIndex != line.startIndex,
               line[line.startIndex..<dotIndex].allSatisfy({ $0.isNumber }),
               line.index(after: dotIndex) < line.endIndex,
               line[line.index(after: dotIndex)] == " " {
                flushParagraph()
                let cleaned = cleanInline(String(line[line.index(dotIndex, offsetBy: 2)...]))
                if !cleaned.isEmpty {
                    blocks.append(.bullet(cleaned))
                }
                continue
            }

            paragraph.append(line)
        }
        if inFence { flushFence() }
        flushParagraph()
        if blocks.count > 24 { blocks = Array(blocks.prefix(24)) }

        return MarkdownSkim(title: title, blocks: blocks)
    }

    /// Inline cleanup: images removed, links unwrapped, emphasis/code/HTML
    /// markers stripped, whitespace collapsed.
    static func cleanInline(_ s: String) -> String {
        // Cap BEFORE the regex passes: the link/HTML patterns backtrack O(n)
        // at each start position, so an adversarial 64KB single line ("[["…)
        // costs tens of seconds and gets the extension killed by QuickLook.
        // A thumbnail only ever displays a few dozen characters anyway.
        var t = String(s.prefix(300))
        t = regexReplace(t, pattern: "!\\[[^\\]]*\\]\\([^)]*\\)", template: "")
        t = regexReplace(t, pattern: "\\[([^\\]]*)\\]\\([^)]*\\)", template: "$1")
        t = regexReplace(t, pattern: "<[^>]+>", template: "")
        for marker in ["**", "__", "~~", "`", "*", "_"] {
            t = t.replacingOccurrences(of: marker, with: "")
        }
        t = regexReplace(t, pattern: "\\s+", template: " ")
        return clampLongTokens(t.trimmingCharacters(in: .whitespaces))
    }

    /// A single unbroken token longer than roughly one line character-wraps
    /// across multiple lines and can dominate the whole page; hard-truncate
    /// any such token with a trailing ellipsis.
    private static func clampLongTokens(_ s: String, limit: Int = 28) -> String {
        guard s.count > limit else { return s }
        return s.split(separator: " ", omittingEmptySubsequences: false)
            .map { token -> String in
                token.count > limit
                    ? String(token.prefix(limit - 1)) + "\u{2026}"
                    : String(token)
            }
            .joined(separator: " ")
    }

    private static func regexReplace(_ s: String, pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length), withTemplate: template
        )
    }

    // MARK: - Page geometry

    /// Letter-ish page aspect (width / height = 0.773), fitted inside
    /// `maximum` and clamped up to at least `minimum`.
    static func pageSize(maximum: CGSize, minimum: CGSize) -> CGSize {
        let aspect: CGFloat = 0.773
        var height = maximum.height
        var width = height * aspect
        if width > maximum.width {
            width = maximum.width
            height = width / aspect
        }
        width = max(width, minimum.width)
        height = max(height, minimum.height)
        return CGSize(width: width, height: height)
    }

    // MARK: - Palette

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private static var pageColor: NSColor { rgb(0xF7, 0xF3, 0xEA) }     // #F7F3EA
    private static var borderColor: NSColor { rgb(0xD9, 0xD3, 0xC6) }   // #D9D3C6
    private static var titleColor: NSColor { rgb(0x15, 0x14, 0x0E) }    // #15140E
    private static var bodyColor: NSColor { rgb(0x15, 0x14, 0x0E) }     // --ink #15140E (app sets .doc p in full ink)
    private static var headingColor: NSColor { rgb(0x2E, 0x2B, 0x20) }  // #2E2B20
    private static var monoColor: NSColor { rgb(0x15, 0x14, 0x0E) }     // --ink #15140E
    private static var chipColor: NSColor { rgb(0xF8, 0xF5, 0xEE) }     // --bg-hi #F8F5EE (lighter than page, like the app)
    private static var ghostColor: NSColor { rgb(0xE4, 0xDE, 0xD2) }    // #E4DED2
    private static var synPurple: NSColor { rgb(0x7A, 0x51, 0xC7) }     // --syn-purple #7A51C7
    private static var synTeal: NSColor { rgb(0x17, 0x7A, 0x6E) }       // --syn-teal #177A6E

    private static var spectralColors: [NSColor] {
        [
            rgb(0xFF, 0x5D, 0x73),  // #FF5D73
            rgb(0xFF, 0xB4, 0x54),  // #FFB454
            rgb(0x36, 0xD6, 0xC3),  // #36D6C3
            rgb(0x6A, 0xA6, 0xFF),  // #6AA6FF
            rgb(0xB0, 0x7B, 0xFF),  // #B07BFF
        ]
    }

    // MARK: - Drawing

    /// Draws the thumbnail into the CURRENT NSGraphicsContext. The context
    /// is non-flipped (origin bottom-left); layout runs top-down with a
    /// y-cursor measured from the top edge, converting per-block:
    /// drawnY = rect.height - cursor - blockHeight.
    static func draw(skim: MarkdownSkim, in rect: CGRect) {
        let s = rect.width

        // Background + inset hairline.
        pageColor.setFill()
        rect.fill()
        borderColor.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let margin = 0.085 * s
        let topMargin = 0.09 * s
        let bottomMargin = 0.08 * s
        let contentW = rect.width - 2 * margin
        var cursor = topMargin
        let maxCursor = rect.height - bottomMargin

        // Title: serif semibold, up to 3 lines, truncating tail.
        let titleFontSize = 0.105 * s
        var titleFont = NSFont.systemFont(ofSize: titleFontSize, weight: .semibold)
        let serifDescriptor = titleFont.fontDescriptor.withDesign(.serif)
        if let serifDescriptor, let serif = NSFont(descriptor: serifDescriptor, size: titleFontSize) {
            titleFont = serif
        }
        let titleHeight = drawTextBlock(
            skim.title,
            font: titleFont,
            color: titleColor,
            lineHeightMultiple: 1.08,
            kern: -0.01 * titleFontSize,
            x: rect.minX + margin,
            width: contentW,
            maxHeight: min(3.4 * titleFontSize, maxCursor - cursor),
            rect: rect,
            cursor: cursor
        )
        cursor += titleHeight

        // Spectral rule. The title's line box already carries ~0.025s of
        // trailing whitespace, so a small code gap here yields an optical
        // title->rule gap of ~34px at 1024 — about half the rule->body gap,
        // so the rule reads as belonging to the title.
        cursor += 0.018 * s
        let ruleH = max(2, 0.007 * s)
        if cursor + ruleH <= maxCursor {
            let ruleRect = CGRect(
                x: rect.minX + margin,
                y: rect.minY + rect.height - cursor - ruleH,
                width: 0.26 * s,
                height: ruleH
            )
            let rulePath = NSBezierPath(roundedRect: ruleRect, xRadius: ruleH / 2, yRadius: ruleH / 2)
            // Exact theme.css --spectral stops, interpolated in sRGB like the
            // CSS gradient, composited at 0.85 alpha over the cream so it
            // reads as the app's quiet h1::after signature, not a stripe.
            let stops = spectralColors.map { $0.withAlphaComponent(0.85) }
            NSGradient(
                colors: stops,
                atLocations: [0, 0.25, 0.5, 0.75, 1],
                colorSpace: .sRGB
            )?.draw(in: rulePath, angle: 0)
        }
        cursor += ruleH
        cursor += 0.055 * s

        // Blocks.
        let bodyFontSize = 0.040 * s
        let bodyFont = NSFont.systemFont(ofSize: bodyFontSize, weight: .regular)
        let headingFont = NSFont.systemFont(ofSize: 0.046 * s, weight: .semibold)
        let monoFontSize = 0.034 * s
        let monoFont = NSFont(name: "Menlo", size: monoFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: monoFontSize, weight: .regular)
        let blockGap = 0.030 * s
        let headingExtraGap = 0.018 * s
        let bulletInset = 0.02 * s
        let chipPad = 0.02 * s
        let chipRadius = 0.015 * s  // ~12px at the 1024 render, matching the app

        var drewAnyBlock = false

        blockLoop: for block in skim.blocks {
            if cursor >= maxCursor - 1 { break }
            var gap = drewAnyBlock ? blockGap : 0
            if case .heading = block { gap += headingExtraGap }

            switch block {
            case .body(let text), .bullet(let text), .heading(let text):
                let isBullet: Bool
                let isHeading: Bool
                if case .bullet = block { isBullet = true } else { isBullet = false }
                if case .heading = block { isHeading = true } else { isHeading = false }

                let font = isHeading ? headingFont : bodyFont
                let color = isHeading ? headingColor : bodyColor
                let inset = isBullet ? bulletInset : 0
                let display = isBullet ? "\u{2013} " + text : text

                let tentative = cursor + gap
                let available = maxCursor - tentative
                let minLine = font.pointSize * 1.32
                if available < minLine { break blockLoop }

                let measured = measureText(
                    display, font: font, lineHeightMultiple: 1.32, kern: 0,
                    width: contentW - inset
                )
                let height = min(measured, available)
                cursor = tentative
                _ = drawTextBlock(
                    display,
                    font: font,
                    color: color,
                    lineHeightMultiple: 1.32,
                    kern: 0,
                    x: rect.minX + margin + inset,
                    width: contentW - inset,
                    maxHeight: height,
                    rect: rect,
                    cursor: cursor
                )
                cursor += height
                drewAnyBlock = true
                if measured > available { break blockLoop }

            case .mono(let lines):
                let text = lines.prefix(6).joined(separator: "\n")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let tentative = cursor + gap
                let available = maxCursor - tentative
                let textH = measureText(
                    text, font: monoFont, lineHeightMultiple: 1.0, kern: 0,
                    width: contentW - 2 * chipPad
                )
                let chipH = textH + 2 * chipPad
                if chipH > available { break blockLoop }
                cursor = tentative
                let chipRect = CGRect(
                    x: rect.minX + margin,
                    y: rect.minY + rect.height - cursor - chipH,
                    width: contentW,
                    height: chipH
                )
                // App light mode: code sits on --bg-hi (lighter than the
                // page) inside a 1px --line border.
                let chipPath = NSBezierPath(
                    roundedRect: chipRect.insetBy(dx: 0.5, dy: 0.5),
                    xRadius: chipRadius, yRadius: chipRadius
                )
                chipColor.setFill()
                chipPath.fill()
                borderColor.setStroke()
                chipPath.lineWidth = 1
                chipPath.stroke()
                let monoText = monoAttributed(text, font: monoFont)
                let monoRect = CGRect(
                    x: rect.minX + margin + chipPad,
                    y: rect.minY + rect.height - (cursor + chipPad) - textH,
                    width: contentW - 2 * chipPad,
                    height: textH
                )
                monoText.draw(
                    with: monoRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                )
                cursor += chipH
                drewAnyBlock = true
            }
        }

        // Ghost paragraph lines when there is nothing to typeset.
        if !drewAnyBlock {
            let ghostH = 0.028 * s
            let ghostGap = 0.030 * s
            let widths: [CGFloat] = [0.92, 0.88, 0.95, 0.84, 0.60]
            ghostColor.setFill()
            for fraction in widths {
                if cursor + ghostH > maxCursor { break }
                let ghostRect = CGRect(
                    x: rect.minX + margin,
                    y: rect.minY + rect.height - cursor - ghostH,
                    width: contentW * fraction,
                    height: ghostH
                )
                NSBezierPath(roundedRect: ghostRect, xRadius: ghostH / 2, yRadius: ghostH / 2).fill()
                cursor += ghostH + ghostGap
            }
        }
    }

    // MARK: - Text helpers

    /// Cross-language keyword set for the tiny code-chip tint; precision
    /// does not matter at thumbnail scale, only that the warm spectral
    /// syntax palette reads.
    private static let monoKeywords: Set<String> = [
        "let", "var", "func", "return", "if", "else", "for", "while",
        "import", "from", "in", "const", "def", "class", "struct", "enum",
        "function", "fn", "pub", "use", "match", "switch", "case", "guard",
        "true", "false", "nil", "null", "None", "new", "static", "void",
        "public", "private", "async", "await", "try", "catch", "throw",
        "type", "interface", "export", "extension", "protocol", "self",
        "this", "and", "or", "not", "print", "println",
    ]

    /// Attributed code-chip text: base ink with keywords tinted
    /// --syn-purple and string literals tinted --syn-teal.
    private static func monoAttributed(_ text: String, font: NSFont) -> NSAttributedString {
        let attr = NSMutableAttributedString(
            string: text,
            attributes: attributes(
                font: font, color: monoColor, lineHeightMultiple: 1.0, kern: 0
            )
        )
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let re = try? NSRegularExpression(pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\b") {
            for m in re.matches(in: text, range: full)
            where monoKeywords.contains(ns.substring(with: m.range)) {
                attr.addAttribute(.foregroundColor, value: synPurple, range: m.range)
            }
        }
        // Strings after keywords so a keyword inside quotes stays teal.
        if let re = try? NSRegularExpression(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'") {
            for m in re.matches(in: text, range: full) {
                attr.addAttribute(.foregroundColor, value: synTeal, range: m.range)
            }
        }
        return attr
    }

    private static func attributes(
        font: NSFont, color: NSColor, lineHeightMultiple: CGFloat, kern: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        // Always word-wrap: .byTruncatingTail in the string-drawing API
        // silently disables wrapping (everything collapses to one line).
        // Tail truncation for overflowing blocks is requested at draw time
        // via the .truncatesLastVisibleLine option instead.
        style.lineBreakMode = .byWordWrapping
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if kern != 0 { attrs[.kern] = kern }
        return attrs
    }

    /// Measures wrapped text height at the given width.
    private static func measureText(
        _ text: String, font: NSFont, lineHeightMultiple: CGFloat, kern: CGFloat, width: CGFloat
    ) -> CGFloat {
        let attributed = NSAttributedString(
            string: text,
            attributes: attributes(
                font: font, color: .black, lineHeightMultiple: lineHeightMultiple, kern: kern
            )
        )
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return ceil(bounds.height)
    }

    /// Draws `text` inside a rect whose top edge sits `cursor` points below
    /// the top of `rect`, clamped to `maxHeight` (truncating tail). Returns
    /// the height actually used.
    @discardableResult
    private static func drawTextBlock(
        _ text: String,
        font: NSFont,
        color: NSColor,
        lineHeightMultiple: CGFloat,
        kern: CGFloat,
        x: CGFloat,
        width: CGFloat,
        maxHeight: CGFloat,
        rect: CGRect,
        cursor: CGFloat
    ) -> CGFloat {
        guard maxHeight > 0 else { return 0 }
        let measured = measureText(
            text, font: font, lineHeightMultiple: lineHeightMultiple, kern: kern, width: width
        )
        let height = min(measured, maxHeight)
        guard height > 0 else { return 0 }
        let attributed = NSAttributedString(
            string: text,
            attributes: attributes(
                font: font, color: color, lineHeightMultiple: lineHeightMultiple, kern: kern
            )
        )
        let drawRect = CGRect(
            x: x,
            y: rect.minY + rect.height - cursor - height,
            width: width,
            height: height
        )
        var options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        if measured > maxHeight {
            options.insert(.truncatesLastVisibleLine)
        }
        attributed.draw(with: drawRect, options: options)
        return height
    }
}

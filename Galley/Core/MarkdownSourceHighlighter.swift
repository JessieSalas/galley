import AppKit

/// Regex-based syntax coloring for the plain-text editor. This is not a
/// Markdown parser — it's a legibility pass so headings, emphasis, code, and
/// links read at a glance while editing raw source. Correctness on
/// pathological input isn't a goal; keeping it fast and simple is.
enum MarkdownSourceHighlighter {

    /// Above this, a full-document regex sweep on every keystroke starts to
    /// lag before the coloring is worth much anyway — skip entirely.
    static let sizeLimit = 300_000

    static func highlight(_ storage: NSTextStorage, palette: ThemePalette, baseFont: NSFont) {
        guard storage.length <= sizeLimit else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        guard full.length > 0 else { return }

        let ink = NSColor(hex: palette.ink) ?? .labelColor
        let accent = NSColor(hex: palette.accent) ?? .controlAccentColor
        let muted = NSColor(hex: palette.muted) ?? .secondaryLabelColor
        let teal = NSColor(hex: palette.synTeal) ?? .systemTeal
        let comment = NSColor(hex: palette.synComment) ?? .secondaryLabelColor
        let bgHi = NSColor(hex: palette.bgHi) ?? .textBackgroundColor

        let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

        storage.beginEditing()
        // Reset only the attributes we own — leave .paragraphStyle (line
        // height, set by the editor) untouched.
        storage.removeAttribute(.backgroundColor, range: full)
        storage.addAttribute(.font, value: baseFont, range: full)
        storage.addAttribute(.foregroundColor, value: ink, range: full)

        // --- Fenced code blocks: scan lines to track fence state, since a
        // single regex can't balance opening/closing ``` markers. ---
        var codeRanges: [NSRange] = []
        var lineStart = 0
        var inFence = false
        var fenceStart = 0
        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            guard lineRange.length > 0 else { break }
            let trimmed = text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") {
                if inFence {
                    codeRanges.append(NSRange(location: fenceStart, length: lineRange.location + lineRange.length - fenceStart))
                    inFence = false
                } else {
                    inFence = true
                    fenceStart = lineRange.location
                }
            }
            lineStart = lineRange.location + lineRange.length
        }
        if inFence {
            codeRanges.append(NSRange(location: fenceStart, length: text.length - fenceStart))
        }
        for range in codeRanges {
            storage.addAttribute(.backgroundColor, value: bgHi, range: range)
            storage.addAttribute(.foregroundColor, value: comment, range: range)
        }

        func isInCode(_ range: NSRange) -> Bool {
            codeRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        // --- Headings ---
        forEachMatch(#"^#{1,6} .*$"#, in: text, options: [.anchorsMatchLines]) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.foregroundColor, value: accent, range: range)
            storage.addAttribute(.font, value: boldFont, range: range)
        }

        // --- Bold ---
        forEachMatch(#"\*\*[^*\n]+\*\*"#, in: text) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.font, value: boldFont, range: range)
        }

        // --- Italic (single asterisk, not part of a ** pair) ---
        forEachMatch(#"(?<!\*)\*[^*\n]+\*(?!\*)"#, in: text) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.font, value: italicFont, range: range)
        }

        // --- Inline code ---
        forEachMatch(#"`[^`\n]+`"#, in: text) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.foregroundColor, value: teal, range: range)
            storage.addAttribute(.backgroundColor, value: bgHi, range: range)
        }

        // --- Blockquotes ---
        forEachMatch(#"^>.*$"#, in: text, options: [.anchorsMatchLines]) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.foregroundColor, value: muted, range: range)
        }

        // --- List markers (marker only, not the item text) ---
        // [ \t]*, not \s* — \s matches newlines, which let a failed match on
        // a marker-less document backtrack across the whole remaining text
        // for every line (quadratic; freezes the editor on large paste-ins).
        forEachMatch(#"^[ \t]*([-*+]|\d+\.) "#, in: text, options: [.anchorsMatchLines]) { range in
            guard !isInCode(range) else { return }
            storage.addAttribute(.foregroundColor, value: accent, range: range)
        }

        // --- Links: [text](url) — brackets/parens muted, text ink, url muted ---
        // Both groups are newline-excluded AND length-capped. Excluding \n
        // alone isn't enough: one huge line full of stray "[" (no closing
        // bracket) still makes each attempt scan to the line's end, which is
        // O(n) per attempt — still quadratic overall. Capping the span makes
        // every attempt O(cap), so total cost is linear in document size.
        // No real link needs a 500-char label or a 2000-char URL.
        forEachMatchGroups(#"\[([^\]\n]{0,500})\]\(([^)\n]{1,2000})\)"#, in: text) { match in
            guard !isInCode(match.range) else { return }
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
            if match.range(at: 1).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: ink, range: match.range(at: 1))
            }
            if match.range(at: 2).location != NSNotFound {
                storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 2))
            }
        }

        // --- Front matter (--- block at the very start of the document) ---
        // Applied last so it wins over any incidental match inside it.
        if let fmRange = frontMatterRange(in: text) {
            storage.addAttribute(.foregroundColor, value: muted, range: fmRange)
        }

        storage.endEditing()
    }

    private static func frontMatterRange(in text: NSString) -> NSRange? {
        guard text.hasPrefix("---") else { return nil }
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        guard text.substring(with: firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        var searchStart = firstLine.location + firstLine.length
        while searchStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: searchStart, length: 0))
            guard lineRange.length > 0 else { break }
            let trimmed = text.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" {
                return NSRange(location: 0, length: lineRange.location + lineRange.length)
            }
            searchStart = lineRange.location + lineRange.length
        }
        return nil
    }

    private static func forEachMatch(
        _ pattern: String,
        in text: NSString,
        options: NSRegularExpression.Options = [],
        body: (NSRange) -> Void
    ) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match else { return }
            body(match.range)
        }
    }

    private static func forEachMatchGroups(
        _ pattern: String,
        in text: NSString,
        options: NSRegularExpression.Options = [],
        body: (NSTextCheckingResult) -> Void
    ) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        re.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match else { return }
            body(match)
        }
    }
}

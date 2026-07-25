// render-thumb-harness.swift
// Dev harness for the GalleyThumbnail renderer: rasterizes ThumbnailRenderer
// output for a directory of Markdown fixtures at several sizes, without any
// QuickLook machinery, so thumbnail layout can be iterated on outside Finder.
//
// ThumbnailRenderer.swift has no QuickLook imports precisely so it can be
// compiled together with this file:
//
//   swiftc -o /tmp/thumbharness \
//       Thumbnail/ThumbnailRenderer.swift scripts/render-thumb-harness.swift \
//       -framework AppKit
//   /tmp/thumbharness <out-dir>
//
// (Not runnable as `swift scripts/render-thumb-harness.swift` alone — the
// interpreter cannot see ThumbnailRenderer, hence the @main struct and the
// two-file swiftc invocation.)
//
// Reads every .md file in /tmp/galley-thumb-fixtures and writes
// <out-dir>/<fixture>-<size>.png for sizes 1024, 256, 96. The canvas for
// each size is ThumbnailRenderer.pageSize(maximum: size x size,
// minimum: 32 x 32), matching what the extension would get from QuickLook.

import AppKit
import Foundation

@main
struct RenderThumbHarness {
    static let fixturesDir = "/tmp/galley-thumb-fixtures"
    static let sizes: [CGFloat] = [1024, 256, 96]

    static func fail(_ msg: String) -> Never {
        FileHandle.standardError.write("render-thumb-harness: \(msg)\n".data(using: .utf8)!)
        exit(1)
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 2 else {
            fail("usage: thumbharness <out-dir>")
        }
        let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let fixturesURL = URL(fileURLWithPath: fixturesDir, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: fixturesURL, includingPropertiesForKeys: nil
        ) else {
            fail("could not list fixtures at \(fixturesDir)")
        }
        let fixtures = entries.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
        guard !fixtures.isEmpty else {
            fail("no .md fixtures in \(fixturesDir)")
        }

        for fixture in fixtures {
            let data = (try? Data(contentsOf: fixture)) ?? Data()
            let skim = ThumbnailRenderer.skim(data: data, filename: fixture.lastPathComponent)
            let name = fixture.deletingPathExtension().lastPathComponent
            for size in sizes {
                let canvas = ThumbnailRenderer.pageSize(
                    maximum: CGSize(width: size, height: size),
                    minimum: CGSize(width: 32, height: 32)
                )
                let outPath = outDir.appendingPathComponent("\(name)-\(Int(size)).png")
                render(skim: skim, canvas: canvas, to: outPath)
            }
        }
    }

    static func render(skim: MarkdownSkim, canvas: CGSize, to url: URL) {
        let pixelW = Int(canvas.width.rounded())
        let pixelH = Int(canvas.height.rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fail("could not create bitmap rep for \(url.path)")
        }
        // Tag the bitmap as sRGB before drawing so the renderer's sRGB
        // palette (theme.css hex values) lands in the PNG byte-for-byte
        // instead of being converted through calibrated/generic RGB.
        let srgbRep = rep.retagging(with: .sRGB) ?? rep
        guard let context = NSGraphicsContext(bitmapImageRep: srgbRep) else {
            fail("could not create graphics context for \(url.path)")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ThumbnailRenderer.draw(
            skim: skim,
            in: CGRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH))
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = srgbRep.representation(using: .png, properties: [:]) else {
            fail("could not encode PNG for \(url.path)")
        }
        do {
            try png.write(to: url)
        } catch {
            fail("could not write \(url.path): \(error)")
        }
        print("wrote \(url.path) (\(pixelW)x\(pixelH))")
    }
}

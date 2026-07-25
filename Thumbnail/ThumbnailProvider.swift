// ThumbnailProvider.swift
// QuickLook thumbnail extension entry point: renders Markdown files as tiny
// typeset pages in Finder. All the actual layout lives in ThumbnailRenderer.

import AppKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let size = ThumbnailRenderer.pageSize(
            maximum: request.maximumSize,
            minimum: request.minimumSize
        )
        let data = (try? Data(contentsOf: request.fileURL, options: .mappedIfSafe)) ?? Data()
        let skim = ThumbnailRenderer.skim(
            data: data,
            filename: request.fileURL.lastPathComponent
        )
        handler(
            QLThumbnailReply(contextSize: size, currentContextDrawing: {
                ThumbnailRenderer.draw(skim: skim, in: CGRect(origin: .zero, size: size))
                return true
            }),
            nil
        )
    }
}

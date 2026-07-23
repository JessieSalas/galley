import SwiftUI
import UniformTypeIdentifiers

/// Read-only document. Galley is a viewer: there is deliberately no write path.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDoc, .plainText] }
    static var writableContentTypes: [UTType] { [] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = Self.decode(data)
    }

    /// UTF-8 first, then common fallbacks — never refuse to open a text file.
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        var converted: NSString?
        NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        if let converted { return converted as String }
        return String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

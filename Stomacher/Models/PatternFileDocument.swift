import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let stomPattern = UTType(exportedAs: "no.abrahamsen.stomacher.pattern", conformingTo: .json)
}

struct PatternFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.stomPattern] }
    static var writableContentTypes: [UTType] { [.stomPattern] }

    var pattern: PatternDocument

    init(pattern: PatternDocument) {
        self.pattern = pattern
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        pattern = try decoder.decode(PatternDocument.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return FileWrapper(regularFileWithContents: try encoder.encode(pattern))
    }
}


import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Packs answered checks into a zip that `make import` on the Mac unpacks into data/raw/:
///
///     CilantroExport/
///       cilantro/app_20261002-121314_1a2b3c4d.jpg   <- "Yes, visible"
///       not_cilantro/...                            <- "No"
///       hidden/...                                  <- "Yes, hidden" (kept for the record, not trained on)
///       labels.csv
enum TrainingExport {
    static func makeZip(_ records: [CheckRecord]) throws -> Data {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let exportDir = workDir.appendingPathComponent("CilantroExport")
        defer { try? fm.removeItem(at: workDir) }

        let nameFormatter = DateFormatter()
        nameFormatter.locale = Locale(identifier: "en_US_POSIX")
        nameFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let isoFormatter = ISO8601DateFormatter()

        var csv = "file,answer,model_cilantro_probability,date\n"
        for record in records {
            guard let feedback = record.feedback else { continue }
            let folder = switch feedback {
            case .visible: "cilantro"
            case .absent: "not_cilantro"
            case .hidden: "hidden"
            }
            let dir = exportDir.appendingPathComponent(folder)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "app_\(nameFormatter.string(from: record.date))_\(UUID().uuidString.prefix(8).lowercased()).jpg"
            try record.imageData.write(to: dir.appendingPathComponent(name))
            csv += "\(folder)/\(name),\(feedback.rawValue),\(record.cilantroProbability),\(isoFormatter.string(from: record.date))\n"
        }
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)
        try csv.write(to: exportDir.appendingPathComponent("labels.csv"), atomically: true, encoding: .utf8)

        // iOS has no public zip API, but asking the file coordinator for a folder
        // "for uploading" hands back a zipped copy of it.
        var zipData: Data?
        var readError: Error?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: exportDir, options: .forUploading, error: &coordinatorError) { zipURL in
            do { zipData = try Data(contentsOf: zipURL) } catch { readError = error }
        }
        if let error = coordinatorError ?? readError { throw error }
        guard let zipData else { throw CocoaError(.fileReadUnknown) }
        return zipData
    }

    static var defaultFilename: String {
        "CilantroExport-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
    }
}

/// Wraps the zip so SwiftUI's `.fileExporter` can save it to Files / iCloud Drive.
struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

import CoreGraphics
import Foundation

enum AtomicFileWriterError: Error {
    case couldNotEncodeJSON
}

enum AtomicFileWriter {
    static func writePNG(_ image: CGImage, to destination: URL, imageWriter: ImageWriter) throws {
        let temporary = temporaryURL(for: destination)
        try imageWriter.writePNG(image, to: temporary.path)
        try replace(temporary: temporary, destination: destination)
    }

    static func writeJSON<T: Encodable>(_ value: T, to destination: URL, statusWriter: StatusWriter) throws {
        let temporary = temporaryURL(for: destination)
        try statusWriter.writeJSON(value, to: temporary)
        try replace(temporary: temporary, destination: destination)
    }

    static func writeText(_ value: String, to destination: URL) throws {
        let temporary = temporaryURL(for: destination)
        try FileManager.default.createDirectory(
            at: temporary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try value.write(to: temporary, atomically: false, encoding: .utf8)
        try replace(temporary: temporary, destination: destination)
    }

    private static func temporaryURL(for destination: URL) -> URL {
        destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
    }

    private static func replace(temporary: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }
}

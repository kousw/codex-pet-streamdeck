import Foundation

final class StatusWriter {
    private let encoder: JSONEncoder

    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    func writeJSON<T: Encodable>(_ value: T, to destination: URL) throws {
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination)
    }
}

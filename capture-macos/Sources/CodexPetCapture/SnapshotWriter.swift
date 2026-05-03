import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SnapshotWriterError: Error {
    case captureReturnedNil
    case couldNotCreateDestination(String)
    case couldNotFinalize(String)
}

final class SnapshotWriter {
    func writeWindowSnapshot(windowID: UInt32, to outputPath: String) throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let image = try captureWindowImage(windowID: windowID)

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SnapshotWriterError.couldNotCreateDestination(outputPath)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw SnapshotWriterError.couldNotFinalize(outputPath)
        }
    }

    func captureWindowImage(windowID: UInt32) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw SnapshotWriterError.captureReturnedNil
        }

        return image
    }
}

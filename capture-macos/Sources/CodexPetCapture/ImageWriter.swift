import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageWriterError: Error {
    case couldNotCreateDestination(String)
    case couldNotFinalize(String)
    case couldNotCreateData
}

final class ImageWriter {
    func writePNG(_ image: CGImage, to outputPath: String) throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageWriterError.couldNotCreateDestination(outputPath)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriterError.couldNotFinalize(outputPath)
        }
    }

    func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageWriterError.couldNotCreateData
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageWriterError.couldNotCreateData
        }

        return data as Data
    }
}

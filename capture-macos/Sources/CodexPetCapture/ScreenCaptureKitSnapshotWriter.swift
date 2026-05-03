import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenCaptureKitSnapshotWriterError: Error {
    case windowNotFound(UInt32)
    case couldNotCreateDestination(String)
    case couldNotFinalize(String)
}

@available(macOS 14.0, *)
final class ScreenCaptureKitSnapshotWriter {
    func writeWindowSnapshot(windowID: UInt32, to outputPath: String) async throws {
        let outputURL = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let image = try await captureWindowImage(windowID: windowID)

        try ImageWriter().writePNG(image, to: outputPath)
    }

    func captureWindowImage(windowID: UInt32) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )

        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(windowID) }) else {
            throw ScreenCaptureKitSnapshotWriterError.windowNotFound(windowID)
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(window.frame.width))
        configuration.height = max(1, Int(window.frame.height))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }
}

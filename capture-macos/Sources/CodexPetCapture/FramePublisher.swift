import CoreGraphics
import Foundation

struct FrameStatus: Codable {
    let version: Int
    let status: String
    let updatedAt: String
    let framePath: String
    let frameSequence: Int
    let frameSlot: Int
    let frameDataPath: String
    let captureMode: String
    let targetWindowID: UInt32
    let message: String?
}

final class FramePublisher {
    private let windowID: UInt32
    private let frameMode: FrameMode
    private let captureEngine: CaptureEngine
    private let fps: Double
    private let outputDirectory: URL
    private let durationSeconds: Double?
    private let debugLogging: Bool
    private let snapshotWriter = ScreenCaptureKitSnapshotWriter()
    private let coreGraphicsSnapshotWriter = SnapshotWriter()
    private let frameRenderer = FrameRenderer()
    private let imageWriter = ImageWriter()
    private let statusWriter = StatusWriter()

    init(
        windowID: UInt32,
        frameMode: FrameMode,
        captureEngine: CaptureEngine,
        fps: Double,
        outputDirectory: String,
        durationSeconds: Double?,
        debugLogging: Bool = false
    ) {
        self.windowID = windowID
        self.frameMode = frameMode
        self.captureEngine = captureEngine
        self.fps = fps
        self.outputDirectory = URL(fileURLWithPath: outputDirectory)
        self.durationSeconds = durationSeconds
        self.debugLogging = debugLogging
    }

    func run() async throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let latestPath = outputDirectory.appendingPathComponent("latest.png")
        let statusPath = outputDirectory.appendingPathComponent("status.json")
        let dataURLPath = outputDirectory.appendingPathComponent("latest-data-url.txt")
        let slotCount = 8
        let startedAt = Date()
        let intervalNanoseconds = UInt64((1_000_000_000.0 / fps).rounded())
        var sequence = 0

        while true {
            let image = try await captureWindowImage()
            let frame = try frameRenderer.render(image: image, mode: frameMode)
            let slot = sequence % slotCount
            let slotPath = outputDirectory.appendingPathComponent("frame-\(slot).png")
            try AtomicFileWriter.writePNG(frame, to: slotPath, imageWriter: imageWriter)
            try AtomicFileWriter.writePNG(frame, to: latestPath, imageWriter: imageWriter)
            try AtomicFileWriter.writeText(dataURL(forPNGAt: latestPath), to: dataURLPath)

            let status = FrameStatus(
                version: 1,
                status: "ok",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                framePath: slotPath.path,
                frameSequence: sequence,
                frameSlot: slot,
                frameDataPath: dataURLPath.path,
                captureMode: frameMode.rawValue,
                targetWindowID: windowID,
                message: nil
            )
            try AtomicFileWriter.writeJSON(status, to: statusPath, statusWriter: statusWriter)

            debug("frame \(sequence) -> \(slotPath.path)")
            sequence += 1

            if let durationSeconds, Date().timeIntervalSince(startedAt) >= durationSeconds {
                return
            }

            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    private func captureWindowImage() async throws -> CGImage {
        switch captureEngine {
        case .coreGraphics:
            return try coreGraphicsSnapshotWriter.captureWindowImage(windowID: windowID)
        case .screenCaptureKit:
            return try await snapshotWriter.captureWindowImage(windowID: windowID)
        }
    }

    private func dataURL(forPNGAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    private func debug(_ message: String) {
        guard debugLogging else {
            return
        }
        print(message)
        fflush(stdout)
    }
}

import CoreGraphics
import Foundation

struct CaptureServiceStatus: Codable {
    let version: Int
    let status: String
    let updatedAt: String
    let framePath: String?
    let frameSequence: Int?
    let frameSlot: Int?
    let frameDataPath: String?
    let captureMode: String?
    let captureFPS: Double?
    let crop: CropConfiguration?
    let targetWindowID: UInt32?
    let message: String?
}

final class FrameService {
    private let bundleIdentifier: String
    private let frameMode: FrameMode
    private let captureEngine: CaptureEngine
    private let fps: Double
    private let retryIntervalSeconds: Double
    private let cropConfiguration: CropConfiguration
    private let outputDirectory: URL
    private let durationSeconds: Double?
    private let discovery: WindowDiscovery
    private let snapshotWriter = ScreenCaptureKitSnapshotWriter()
    private let coreGraphicsSnapshotWriter = SnapshotWriter()
    private let frameRenderer: FrameRenderer
    private let imageWriter = ImageWriter()
    private let statusWriter = StatusWriter()
    private let slotCount = 8

    init(
        bundleIdentifier: String,
        frameMode: FrameMode,
        captureEngine: CaptureEngine,
        fps: Double,
        retryIntervalSeconds: Double,
        cropConfiguration: CropConfiguration,
        outputDirectory: String,
        durationSeconds: Double?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.frameMode = frameMode
        self.captureEngine = captureEngine
        self.fps = fps
        self.retryIntervalSeconds = retryIntervalSeconds
        self.cropConfiguration = cropConfiguration
        self.outputDirectory = URL(fileURLWithPath: outputDirectory)
        self.durationSeconds = durationSeconds
        self.discovery = WindowDiscovery(targetBundleIdentifier: bundleIdentifier)
        self.frameRenderer = FrameRenderer(cropConfiguration: cropConfiguration)
    }

    func run() async throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let startedAt = Date()
        let frameIntervalNanoseconds = UInt64((1_000_000_000.0 / fps).rounded())
        let retryIntervalNanoseconds = UInt64((1_000_000_000.0 * retryIntervalSeconds).rounded())
        var sequence = 0

        while true {
            if let durationSeconds, Date().timeIntervalSince(startedAt) >= durationSeconds {
                return
            }

            guard let selectedWindow = WindowSelector.bestPetOverlayWindow(from: discovery.listWindows()) else {
                try writeServiceStatus(status: "window-not-found", message: "No onscreen Codex pet overlay window found for \(bundleIdentifier).")
                try await Task.sleep(nanoseconds: retryIntervalNanoseconds)
                continue
            }

            do {
                try await publishFrame(windowID: selectedWindow.windowID, sequence: sequence)
                sequence += 1
                try await Task.sleep(nanoseconds: frameIntervalNanoseconds)
            } catch {
                try writeServiceStatus(
                    status: "capture-failed",
                    targetWindowID: selectedWindow.windowID,
                    message: String(describing: error)
                )
                try await Task.sleep(nanoseconds: retryIntervalNanoseconds)
            }
        }
    }

    private func publishFrame(windowID: UInt32, sequence: Int) async throws {
        let image = try await captureWindowImage(windowID: windowID)
        let frame = try frameRenderer.render(image: image, mode: frameMode)
        let slot = sequence % slotCount
        let latestPath = outputDirectory.appendingPathComponent("latest.png")
        let statusPath = outputDirectory.appendingPathComponent("status.json")
        let dataURLPath = outputDirectory.appendingPathComponent("latest-data-url.txt")
        let slotPath = outputDirectory.appendingPathComponent("frame-\(slot).png")
        let pngData = try imageWriter.pngData(frame)

        try AtomicFileWriter.writePNG(frame, to: slotPath, imageWriter: imageWriter)
        try AtomicFileWriter.writePNG(frame, to: latestPath, imageWriter: imageWriter)
        try AtomicFileWriter.writeText(dataURL(forPNGData: pngData), to: dataURLPath)

        let status = CaptureServiceStatus(
            version: 1,
            status: "ok",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            framePath: slotPath.path,
            frameSequence: sequence,
            frameSlot: slot,
            frameDataPath: dataURLPath.path,
            captureMode: frameMode.rawValue,
            captureFPS: fps,
            crop: cropConfiguration,
            targetWindowID: windowID,
            message: nil
        )
        try AtomicFileWriter.writeJSON(status, to: statusPath, statusWriter: statusWriter)

        print("frame \(sequence) -> \(slotPath.path)")
        fflush(stdout)
    }

    private func captureWindowImage(windowID: UInt32) async throws -> CGImage {
        switch captureEngine {
        case .coreGraphics:
            return try coreGraphicsSnapshotWriter.captureWindowImage(windowID: windowID)
        case .screenCaptureKit:
            return try await snapshotWriter.captureWindowImage(windowID: windowID)
        }
    }

    private func writeServiceStatus(
        status: String,
        targetWindowID: UInt32? = nil,
        message: String
    ) throws {
        let statusPath = outputDirectory.appendingPathComponent("status.json")
        let value = CaptureServiceStatus(
            version: 1,
            status: status,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            framePath: nil,
            frameSequence: nil,
            frameSlot: nil,
            frameDataPath: nil,
            captureMode: frameMode.rawValue,
            captureFPS: fps,
            crop: cropConfiguration,
            targetWindowID: targetWindowID,
            message: message
        )
        try AtomicFileWriter.writeJSON(value, to: statusPath, statusWriter: statusWriter)
        print("\(status): \(message)")
        fflush(stdout)
    }

    private func dataURL(forPNGData data: Data) -> String {
        "data:image/png;base64,\(data.base64EncodedString())"
    }
}

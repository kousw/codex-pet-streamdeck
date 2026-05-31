import Foundation

struct ProbeConfiguration {
    let bundleIdentifier: String
    let snapshotBest: Bool
    let snapshotWindowID: UInt32?
    let screenCaptureKitSnapshotBest: Bool
    let screenCaptureKitSnapshotWindowID: UInt32?
    let screenCaptureKitFrameBest: Bool
    let screenCaptureKitFrameWindowID: UInt32?
    let cropPreviewBest: Bool
    let cropPreviewWindowID: UInt32?
    let publishBest: Bool
    let publishWindowID: UInt32?
    let serve: Bool
    let renderAssets: Bool
    let frameMode: FrameMode
    let captureEngine: CaptureEngine
    let fps: Double
    let retryIntervalSeconds: Double
    let cropConfiguration: CropConfiguration
    let durationSeconds: Double?
    let outputDirectory: String
    let outputPath: String?
    let requestScreenRecordingAccess: Bool
    let petID: String?
    let petState: PetAnimationState?
    let debugLogging: Bool

    init(arguments: [String]) {
        let renderAssetsFlag = arguments.contains("--render-assets")
        self.bundleIdentifier = Self.value(after: "--bundle-id", in: arguments)
            ?? "com.openai.codex"
        self.snapshotBest = arguments.contains("--snapshot-best")
        self.snapshotWindowID = Self.value(after: "--snapshot-window-id", in: arguments)
            .flatMap(UInt32.init)
        self.screenCaptureKitSnapshotBest = arguments.contains("--sck-snapshot-best")
        self.screenCaptureKitSnapshotWindowID = Self.value(after: "--sck-snapshot-window-id", in: arguments)
            .flatMap(UInt32.init)
        self.screenCaptureKitFrameBest = arguments.contains("--sck-frame-best")
        self.screenCaptureKitFrameWindowID = Self.value(after: "--sck-frame-window-id", in: arguments)
            .flatMap(UInt32.init)
        self.cropPreviewBest = arguments.contains("--crop-preview-best")
        self.cropPreviewWindowID = Self.value(after: "--crop-preview-window-id", in: arguments)
            .flatMap(UInt32.init)
        self.publishBest = arguments.contains("--publish-best")
        self.publishWindowID = Self.value(after: "--publish-window-id", in: arguments)
            .flatMap(UInt32.init)
        self.serve = arguments.contains("--serve")
        self.renderAssets = renderAssetsFlag
        self.frameMode = Self.value(after: "--frame-mode", in: arguments)
            .flatMap(FrameMode.init(rawValue:))
            ?? .pet
        self.captureEngine = Self.value(after: "--capture-engine", in: arguments)
            .flatMap(CaptureEngine.init(rawValue:))
            ?? .coreGraphics
        self.fps = Self.value(after: "--fps", in: arguments)
            .flatMap(Double.init)
            .map { min(max($0, 1), 15) }
            ?? (renderAssetsFlag ? 10 : 1)
        self.retryIntervalSeconds = Self.value(after: "--retry-interval", in: arguments)
            .flatMap(Double.init)
            .map { max($0, 0.25) }
            ?? 2
        self.cropConfiguration = CropConfiguration(
            x: Self.value(after: "--crop-x", in: arguments).flatMap(Double.init) ?? CropConfiguration.default.x,
            y: Self.value(after: "--crop-y", in: arguments).flatMap(Double.init) ?? CropConfiguration.default.y,
            width: Self.value(after: "--crop-width", in: arguments).flatMap(Double.init) ?? CropConfiguration.default.width,
            height: Self.value(after: "--crop-height", in: arguments).flatMap(Double.init) ?? CropConfiguration.default.height
        )
        self.durationSeconds = Self.value(after: "--duration", in: arguments)
            .flatMap(Double.init)
            .map { max($0, 0) }
        self.outputDirectory = Self.value(after: "--output-dir", in: arguments)
            ?? "/tmp/codex-pet-streamdeck"
        self.outputPath = Self.value(after: "--output", in: arguments)
        self.requestScreenRecordingAccess = arguments.contains("--request-screen-recording-access")
        self.petID = Self.value(after: "--pet-id", in: arguments)
        self.petState = Self.value(after: "--pet-state", in: arguments)
            .flatMap(PetAnimationState.init(rawValue:))
        self.debugLogging = arguments.contains("--debug")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
    }
}

enum FrameMode: String {
    case pet
    case petWithBubble = "pet-with-bubble"
    case debugWide = "debug-wide"
}

enum CaptureEngine: String {
    case coreGraphics = "core-graphics"
    case screenCaptureKit = "screen-capture-kit"
}

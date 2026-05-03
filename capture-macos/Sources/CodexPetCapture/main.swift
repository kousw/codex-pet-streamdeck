import Foundation

await run()

private func run() async {
    let configuration = ProbeConfiguration(arguments: CommandLine.arguments)
    let screenRecordingAccess = ScreenRecordingAccess(
        isGranted: ScreenRecordingPermission.isGranted(requestIfMissing: configuration.requestScreenRecordingAccess)
    )

    if configuration.serve {
        await runService(configuration: configuration, screenRecordingAccess: screenRecordingAccess)
        return
    }

    let discovery = WindowDiscovery(targetBundleIdentifier: configuration.bundleIdentifier)
    let windows = discovery.listWindows()

    if configuration.snapshotBest || configuration.snapshotWindowID != nil {
        await runCoreGraphicsSnapshot(configuration: configuration, windows: windows, screenRecordingAccess: screenRecordingAccess)
        return
    }

    if configuration.screenCaptureKitSnapshotBest || configuration.screenCaptureKitSnapshotWindowID != nil {
        await runScreenCaptureKitSnapshot(configuration: configuration, windows: windows, screenRecordingAccess: screenRecordingAccess)
        return
    }

    if configuration.screenCaptureKitFrameBest || configuration.screenCaptureKitFrameWindowID != nil {
        await runScreenCaptureKitFrame(configuration: configuration, windows: windows, screenRecordingAccess: screenRecordingAccess)
        return
    }

    if configuration.cropPreviewBest || configuration.cropPreviewWindowID != nil {
        await runCropPreview(configuration: configuration, windows: windows, screenRecordingAccess: screenRecordingAccess)
        return
    }

    if configuration.publishBest || configuration.publishWindowID != nil {
        await runPublisher(configuration: configuration, windows: windows, screenRecordingAccess: screenRecordingAccess)
        return
    }

    printProbeReport(
        configuration: configuration,
        windows: windows,
        screenRecordingAccess: screenRecordingAccess
    )
}

private func runCropPreview(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        fputs("Run with --request-screen-recording-access to trigger the macOS prompt, then re-run after granting access.\n", stderr)
        exit(3)
    }

    guard let selectedWindow = selectSnapshotWindow(from: windows, mode: .cropPreview, configuration: configuration) else {
        fputs("No matching Codex window found for crop preview.\n", stderr)
        exit(2)
    }

    let outputDirectory = URL(fileURLWithPath: configuration.outputDirectory)
    let sourcePath = outputDirectory.appendingPathComponent("crop-source.png")
    let previewPath = outputDirectory.appendingPathComponent("crop-preview.png")
    let framePath = outputDirectory.appendingPathComponent("crop-frame.png")
    do {
        let image = try SnapshotWriter().captureWindowImage(windowID: selectedWindow.windowID)
        let renderer = FrameRenderer(cropConfiguration: configuration.cropConfiguration)
        let preview = try renderer.renderCropPreview(image: image)
        let frame = try renderer.render(image: image, mode: configuration.frameMode)
        let imageWriter = ImageWriter()
        try imageWriter.writePNG(image, to: sourcePath.path)
        try imageWriter.writePNG(preview, to: previewPath.path)
        try imageWriter.writePNG(frame, to: framePath.path)
        print(sourcePath.path)
        print(previewPath.path)
        print(framePath.path)
        exit(0)
    } catch {
        fputs("Failed to write crop preview: \(error)\n", stderr)
        exit(1)
    }
}

private func runService(
    configuration: ProbeConfiguration,
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        writeDeniedStatus(configuration: configuration)
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        fputs("Run with --request-screen-recording-access to trigger the macOS prompt, then re-run after granting access.\n", stderr)
        exit(3)
    }

    do {
        try await FrameService(
            bundleIdentifier: configuration.bundleIdentifier,
            frameMode: configuration.frameMode,
            captureEngine: configuration.captureEngine,
            fps: configuration.fps,
            retryIntervalSeconds: configuration.retryIntervalSeconds,
            cropConfiguration: configuration.cropConfiguration,
            outputDirectory: configuration.outputDirectory,
            durationSeconds: configuration.durationSeconds
        ).run()
        exit(0)
    } catch {
        fputs("Service failed: \(error)\n", stderr)
        exit(1)
    }
}

private func writeDeniedStatus(configuration: ProbeConfiguration) {
    let outputDirectory = URL(fileURLWithPath: configuration.outputDirectory)
    let statusPath = outputDirectory.appendingPathComponent("status.json")
    let status = CaptureServiceStatus(
        version: 1,
        status: "screen-recording-denied",
        updatedAt: ISO8601DateFormatter().string(from: Date()),
        framePath: nil,
        frameSequence: nil,
        frameSlot: nil,
        frameDataPath: nil,
        captureMode: configuration.frameMode.rawValue,
        captureFPS: configuration.fps,
        crop: configuration.cropConfiguration,
        targetWindowID: nil,
        message: "Screen Recording permission is not granted for Codex Pet Capture."
    )

    do {
        try AtomicFileWriter.writeJSON(status, to: statusPath, statusWriter: StatusWriter())
    } catch {
        fputs("Failed to write denied status: \(error)\n", stderr)
    }
}

private func runPublisher(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        exit(3)
    }

    guard let selectedWindow = selectSnapshotWindow(from: windows, mode: .publisher, configuration: configuration) else {
        fputs("No matching Codex window found for publisher.\n", stderr)
        exit(2)
    }

    do {
        try await FramePublisher(
            windowID: selectedWindow.windowID,
            frameMode: configuration.frameMode,
            captureEngine: configuration.captureEngine,
            fps: configuration.fps,
            outputDirectory: configuration.outputDirectory,
            durationSeconds: configuration.durationSeconds
        ).run()
        exit(0)
    } catch {
        fputs("Publisher failed: \(error)\n", stderr)
        exit(1)
    }
}

private func runScreenCaptureKitFrame(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        exit(3)
    }

    guard let selectedWindow = selectSnapshotWindow(from: windows, mode: .screenCaptureKitFrame, configuration: configuration) else {
        fputs("No matching Codex window found for ScreenCaptureKit frame.\n", stderr)
        exit(2)
    }

    let outputPath = configuration.outputPath ?? "/tmp/codex-pet-streamdeck/latest.png"
    do {
        let image = try await ScreenCaptureKitSnapshotWriter().captureWindowImage(windowID: selectedWindow.windowID)
        let frame = try FrameRenderer(cropConfiguration: configuration.cropConfiguration).render(image: image, mode: configuration.frameMode)
        try ImageWriter().writePNG(frame, to: outputPath)
        print(outputPath)
        exit(0)
    } catch {
        fputs("Failed to write Stream Deck frame: \(error)\n", stderr)
        exit(1)
    }
}

private func runCoreGraphicsSnapshot(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        fputs("Run with --request-screen-recording-access to trigger the macOS prompt, then re-run after granting access.\n", stderr)
        exit(3)
    }

    guard let selectedWindow = selectSnapshotWindow(from: windows, mode: .coreGraphics, configuration: configuration) else {
        fputs("No matching Codex window found for snapshot.\n", stderr)
        exit(2)
    }

    let outputPath = configuration.outputPath ?? "/tmp/codex-pet-streamdeck/window-\(selectedWindow.windowID).png"
    do {
        try SnapshotWriter().writeWindowSnapshot(windowID: selectedWindow.windowID, to: outputPath)
        print(outputPath)
        exit(0)
    } catch {
        fputs("Failed to write window snapshot: \(error)\n", stderr)
        exit(1)
    }
}

private func runScreenCaptureKitSnapshot(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) async {
    guard screenRecordingAccess.isGranted else {
        fputs("Screen Recording permission is not granted for this helper.\n", stderr)
        fputs("Run with --request-screen-recording-access to trigger the macOS prompt, then re-run after granting access.\n", stderr)
        exit(3)
    }

    guard let selectedWindow = selectSnapshotWindow(from: windows, mode: .screenCaptureKit, configuration: configuration) else {
        fputs("No matching Codex window found for ScreenCaptureKit snapshot.\n", stderr)
        exit(2)
    }

    let outputPath = configuration.outputPath ?? "/tmp/codex-pet-streamdeck/sck-window-\(selectedWindow.windowID).png"
    do {
        try await ScreenCaptureKitSnapshotWriter().writeWindowSnapshot(windowID: selectedWindow.windowID, to: outputPath)
        print(outputPath)
        exit(0)
    } catch {
        fputs("Failed to write ScreenCaptureKit window snapshot: \(error)\n", stderr)
        exit(1)
    }
}

private func printProbeReport(
    configuration: ProbeConfiguration,
    windows: [WindowInfo],
    screenRecordingAccess: ScreenRecordingAccess
) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let report = ProbeReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        targetBundleIdentifier: configuration.bundleIdentifier,
        screenRecordingAccess: screenRecordingAccess,
        windowCount: windows.count,
        windows: windows
    )

    do {
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(windows.isEmpty ? 2 : 0)
    } catch {
        fputs("Failed to encode probe report: \(error)\n", stderr)
        exit(1)
    }
}

private enum SnapshotMode {
    case coreGraphics
    case screenCaptureKit
    case screenCaptureKitFrame
    case cropPreview
    case publisher
}

private func selectSnapshotWindow(
    from windows: [WindowInfo],
    mode: SnapshotMode,
    configuration: ProbeConfiguration
) -> WindowInfo? {
    let explicitWindowID: UInt32?
    switch mode {
    case .coreGraphics:
        explicitWindowID = configuration.snapshotWindowID
    case .screenCaptureKit:
        explicitWindowID = configuration.screenCaptureKitSnapshotWindowID
    case .screenCaptureKitFrame:
        explicitWindowID = configuration.screenCaptureKitFrameWindowID
    case .cropPreview:
        explicitWindowID = configuration.cropPreviewWindowID
    case .publisher:
        explicitWindowID = configuration.publishWindowID
    }

    if let explicitWindowID {
        return windows.first { $0.windowID == explicitWindowID }
    }

    return WindowSelector.bestPetOverlayWindow(from: windows)
}

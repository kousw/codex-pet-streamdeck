import AppKit
import Foundation

private let helperLabel = "com.kousw.codex-pet-capture"
private let pluginName = "com.kousw.codex-pet.sdPlugin"

private struct FrameStatus: Decodable {
    let status: String
    let updatedAt: String
    let frameSequence: Int?
    let captureFPS: Double?
    let renderFPS: Double?
    let source: String?
    let petState: String?
    let targetWindowID: UInt32?
    let message: String?
}

private struct CaptureConfig {
    var fps: Double = 1
    var retryInterval: Double = 2
    var helperMode: String = "render-assets"
    var petID: String = ""
    var petState: String = ""
    var frameMode: String = "pet"
    var captureEngine: String = "core-graphics"
    var cropX: Double = 248
    var cropY: Double = 222
    var cropWidth: Double = 89
    var cropHeight: Double = 89
}

private final class CropPreviewView: NSView {
    enum DragMode {
        case none
        case move
        case left
        case right
        case top
        case bottom
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    var image: NSImage? {
        didSet { needsDisplay = true }
    }
    var crop = CGRect(x: 248, y: 222, width: 89, height: 89) {
        didSet { needsDisplay = true }
    }
    var onCropChanged: ((CGRect, Bool) -> Void)?

    private let referenceSize = CGSize(width: 356, height: 320)
    private let handleThreshold: CGFloat = 9
    private var dragMode: DragMode = .none
    private var dragStartPoint = CGPoint.zero
    private var dragStartCrop = CGRect.zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        if let image {
            image.draw(
                in: imageRect(),
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
        }

        let rect = displayRect(for: crop)
        NSColor.systemRed.withAlphaComponent(0.18).setFill()
        rect.fill()
        NSColor.systemRed.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 2
        outline.stroke()

        NSColor.white.setFill()
        for handle in handleRects(for: rect) {
            NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragMode = dragMode(at: point)
        dragStartPoint = point
        dragStartCrop = crop
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragMode != .none else {
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let scale = imageScale()
        guard scale.x > 0, scale.y > 0 else {
            return
        }

        let dx = (point.x - dragStartPoint.x) / scale.x
        let dy = (point.y - dragStartPoint.y) / scale.y
        crop = normalizedCrop(from: dragStartCrop, dx: dx, dy: dy, mode: dragMode)
        onCropChanged?(crop, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragMode != .none else {
            return
        }

        dragMode = .none
        onCropChanged?(crop, true)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func imageRect() -> CGRect {
        let scale = min(bounds.width / referenceSize.width, bounds.height / referenceSize.height)
        let width = referenceSize.width * scale
        let height = referenceSize.height * scale
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func imageScale() -> CGPoint {
        let rect = imageRect()
        return CGPoint(x: rect.width / referenceSize.width, y: rect.height / referenceSize.height)
    }

    private func displayRect(for crop: CGRect) -> CGRect {
        let rect = imageRect()
        let scale = imageScale()
        return CGRect(
            x: rect.minX + crop.minX * scale.x,
            y: rect.minY + crop.minY * scale.y,
            width: crop.width * scale.x,
            height: crop.height * scale.y
        )
    }

    private func dragMode(at point: CGPoint) -> DragMode {
        let rect = displayRect(for: crop)
        guard rect.insetBy(dx: -handleThreshold, dy: -handleThreshold).contains(point) else {
            return .none
        }

        let nearLeft = abs(point.x - rect.minX) <= handleThreshold
        let nearRight = abs(point.x - rect.maxX) <= handleThreshold
        let nearTop = abs(point.y - rect.minY) <= handleThreshold
        let nearBottom = abs(point.y - rect.maxY) <= handleThreshold

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, false, true, false):
            return .topLeft
        case (false, true, true, false):
            return .topRight
        case (true, false, false, true):
            return .bottomLeft
        case (false, true, false, true):
            return .bottomRight
        case (true, false, false, false):
            return .left
        case (false, true, false, false):
            return .right
        case (false, false, true, false):
            return .top
        case (false, false, false, true):
            return .bottom
        default:
            return rect.contains(point) ? .move : .none
        }
    }

    private func normalizedCrop(from start: CGRect, dx: CGFloat, dy: CGFloat, mode: DragMode) -> CGRect {
        var x = start.minX
        var y = start.minY
        var width = start.width
        var height = start.height
        let minSize: CGFloat = 8

        switch mode {
        case .move:
            x += dx
            y += dy
        case .left:
            x += dx
            width -= dx
        case .right:
            width += dx
        case .top:
            y += dy
            height -= dy
        case .bottom:
            height += dy
        case .topLeft:
            x += dx
            width -= dx
            y += dy
            height -= dy
        case .topRight:
            width += dx
            y += dy
            height -= dy
        case .bottomLeft:
            x += dx
            width -= dx
            height += dy
        case .bottomRight:
            width += dx
            height += dy
        case .none:
            break
        }

        if width < minSize {
            if mode == .left || mode == .topLeft || mode == .bottomLeft {
                x -= minSize - width
            }
            width = minSize
        }
        if height < minSize {
            if mode == .top || mode == .topLeft || mode == .topRight {
                y -= minSize - height
            }
            height = minSize
        }

        x = min(max(0, x), referenceSize.width - minSize)
        y = min(max(0, y), referenceSize.height - minSize)
        width = min(width, referenceSize.width - x)
        height = min(height, referenceSize.height - y)

        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    private func handleRects(for rect: CGRect) -> [CGRect] {
        let size: CGFloat = 7
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        return points.map { point in
            CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        }
    }
}

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 28)
    private let statusLine = NSMenuItem(title: "Status: unknown", action: nil, keyEquivalent: "")
    private let frameLine = NSMenuItem(title: "Frame: unknown", action: nil, keyEquivalent: "")
    private let windowLine = NSMenuItem(title: "Window: unknown", action: nil, keyEquivalent: "")
    private let configLine = NSMenuItem(title: "Config: unknown", action: nil, keyEquivalent: "")
    private let messageLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var refreshTimer: Timer?
    private var fpsMenuItems: [NSMenuItem] = []
    private var cropWindow: NSWindow?
    private var cropPreviewView: CropPreviewView?
    private var cropFrameImageView: NSImageView?
    private var cropValueFields: [String: NSTextField] = [:]
    private var cropSteppers: [String: NSStepper] = [:]
    private var cropStatusLabel: NSTextField?

    private var launchAgentPath: String {
        "\(NSHomeDirectory())/Library/LaunchAgents/\(helperLabel).plist"
    }

    private var configPath: String {
        "\(NSHomeDirectory())/Library/Application Support/Codex Pet StreamDeck/config.env"
    }

    private var pluginPath: String {
        "\(NSHomeDirectory())/Library/Application Support/com.elgato.StreamDeck/Plugins/\(pluginName)"
    }

    private var framesPath: String {
        "\(pluginPath)/frames"
    }

    private var statusPath: String {
        "\(framesPath)/status.json"
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: pluginPath)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var helperAppPath: String {
        repositoryRoot
            .appendingPathComponent("dist")
            .appendingPathComponent("Codex Pet Capture.app")
            .path
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refreshStatus()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        if CommandLine.arguments.contains("--open-crop-tuner") {
            openCropTuner()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.image = makeMenuBarIcon(hasIssue: false)
            button.imagePosition = .imageOnly
            button.toolTip = "Codex Pet Stream Deck"
        }

        let menu = NSMenu()
        statusLine.isEnabled = false
        frameLine.isEnabled = false
        windowLine.isEnabled = false
        configLine.isEnabled = false
        messageLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(frameLine)
        menu.addItem(windowLine)
        menu.addItem(configLine)
        menu.addItem(messageLine)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Start Helper", action: #selector(startHelper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Stop Helper", action: #selector(stopHelper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Restart Helper", action: #selector(restartHelper), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshStatus), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(settingsMenuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Codex", action: #selector(openCodex), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Frames Folder", action: #selector(openFramesFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Stream Deck Plugins Folder", action: #selector(openPluginFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Config File", action: #selector(openConfigFile), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
    }

    private func settingsMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        let menu = NSMenu()

        let fpsParent = NSMenuItem(title: "Frame FPS", action: nil, keyEquivalent: "")
        let fpsMenu = NSMenu()
        fpsMenuItems = [1, 2, 5, 8, 10, 15].map { value in
            let item = NSMenuItem(title: formatFPS(Double(value)), action: #selector(setFPS(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Double(value)
            fpsMenu.addItem(item)
            return item
        }
        fpsParent.submenu = fpsMenu
        menu.addItem(fpsParent)

        let cropTuner = NSMenuItem(title: "Capture Fallback Crop Tuner", action: #selector(openCropTuner), keyEquivalent: "")
        cropTuner.target = self
        menu.addItem(cropTuner)

        let note = NSMenuItem(title: "Crop applies only when HELPER_MODE is capture-overlay", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)

        parent.submenu = menu
        return parent
    }

    @objc private func startHelper() {
        guard FileManager.default.fileExists(atPath: launchAgentPath) else {
            showStatus(status: "not-installed", message: "Run scripts/install.sh first.")
            return
        }

        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentPath])
        terminateCaptureProcess()
        let bootstrap = runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", launchAgentPath])
        if bootstrap.exitCode != 0 {
            showStatus(status: "start-failed", message: bootstrap.output)
            return
        }

        _ = runLaunchctl(arguments: ["kickstart", "-k", "gui/\(getuid())/\(helperLabel)"])
        refreshStatus()
    }

    @objc private func stopHelper() {
        _ = runLaunchctl(arguments: ["bootout", "gui/\(getuid())", launchAgentPath])
        terminateCaptureProcess()
        refreshStatus()
    }

    @objc private func restartHelper() {
        stopHelper()
        startHelper()
    }

    @objc private func setFPS(_ sender: NSMenuItem) {
        guard let fps = sender.representedObject as? Double else {
            return
        }

        var config = readCaptureConfig()
        config.fps = fps
        writeCaptureConfig(config)
        restartHelper()
    }

    @objc private func adjustCrop(_ sender: NSMenuItem) {
        guard let operation = sender.representedObject as? String else {
            return
        }

        var config = readCaptureConfig()
        let step = 4.0

        switch operation {
        case "left":
            config.cropX -= step
        case "right":
            config.cropX += step
        case "up":
            config.cropY -= step
        case "down":
            config.cropY += step
        case "wider":
            config.cropWidth += step
        case "narrower":
            config.cropWidth = max(8, config.cropWidth - step)
        case "taller":
            config.cropHeight += step
        case "shorter":
            config.cropHeight = max(8, config.cropHeight - step)
        case "reset":
            config.cropX = 248
            config.cropY = 222
            config.cropWidth = 89
            config.cropHeight = 89
        default:
            return
        }

        config.cropX = max(0, config.cropX)
        config.cropY = max(0, config.cropY)
        writeCaptureConfig(config)
        restartHelper()
    }

    @objc private func refreshStatus() {
        let helperState = isHelperLoaded() ? "running" : "stopped"
        let config = readCaptureConfig()
        updateFPSMenu()
        guard let status = readFrameStatus() else {
            configLine.title = configSummary(config)
            showStatus(status: helperState, message: "No frame status yet.")
            return
        }

        let fps = (status.renderFPS ?? status.captureFPS).map { formatFPS($0) } ?? "unknown"
        let source = status.source ?? "capture"
        statusLine.title = "Helper: \(helperState), frame: \(status.status), fps: \(fps)"
        frameLine.title = "Frame: \(status.frameSequence.map(String.init) ?? "unknown")"
        if source == "asset-renderer" {
            windowLine.title = "Renderer: \(status.petState ?? "unknown")"
        } else {
            windowLine.title = "Window: \(status.targetWindowID.map(String.init) ?? "unknown")"
        }
        configLine.title = configSummary(config)
        messageLine.title = status.message ?? "Updated: \(status.updatedAt)"
        applyMenuBarIcon(hasIssue: status.status != "ok")
    }

    @objc private func openCodex() {
        if let url = URL(string: "codex://") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openCropTuner() {
        if let cropWindow {
            cropWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshCropTunerFields()
            refreshCropPreview()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 690, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Codex Pet Crop Tuner"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        let content = NSView(frame: window.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let previewTitle = makeLabel("Overlay crop preview", frame: NSRect(x: 20, y: 480, width: 280, height: 20))
        content.addSubview(previewTitle)
        let previewHint = NSTextField(labelWithString: "Drag the rectangle to move it. Drag edges or corners to resize.")
        previewHint.frame = NSRect(x: 20, y: 458, width: 356, height: 18)
        previewHint.textColor = .secondaryLabelColor
        previewHint.font = .systemFont(ofSize: 11)
        content.addSubview(previewHint)

        let preview = CropPreviewView(frame: NSRect(x: 20, y: 132, width: 356, height: 320))
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.black.cgColor
        preview.onCropChanged = { [weak self] crop, finished in
            Task { @MainActor in
                self?.applyCropFromPreview(crop, refreshFrame: finished)
            }
        }
        content.addSubview(preview)
        cropPreviewView = preview

        let frameTitle = makeLabel("Stream Deck frame", frame: NSRect(x: 418, y: 480, width: 180, height: 20))
        content.addSubview(frameTitle)

        let frameView = NSImageView(frame: NSRect(x: 418, y: 316, width: 144, height: 144))
        frameView.imageScaling = .scaleNone
        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(frameView)
        cropFrameImageView = frameView

        cropValueFields.removeAll()
        cropSteppers.removeAll()
        addCropControl(key: "x", title: "X", y: 260, to: content)
        addCropControl(key: "y", title: "Y", y: 220, to: content)
        addCropControl(key: "width", title: "Width", y: 180, to: content)
        addCropControl(key: "height", title: "Height", y: 140, to: content)

        let saveButton = NSButton(title: "Save & Restart Helper", target: self, action: #selector(saveCropAndRestart))
        saveButton.frame = NSRect(x: 418, y: 90, width: 170, height: 32)
        content.addSubview(saveButton)

        let resetButton = NSButton(title: "Reset", target: self, action: #selector(resetCropFromTuner))
        resetButton.frame = NSRect(x: 596, y: 90, width: 70, height: 32)
        content.addSubview(resetButton)

        let refreshButton = NSButton(title: "Refresh Preview", target: self, action: #selector(refreshCropPreview))
        refreshButton.frame = NSRect(x: 418, y: 52, width: 170, height: 32)
        content.addSubview(refreshButton)

        let permissionButton = NSButton(title: "Request Permission", target: self, action: #selector(requestScreenRecordingPermission))
        permissionButton.frame = NSRect(x: 596, y: 52, width: 140, height: 32)
        content.addSubview(permissionButton)

        let status = NSTextField(labelWithString: "")
        status.frame = NSRect(x: 20, y: 18, width: 646, height: 20)
        status.textColor = .secondaryLabelColor
        content.addSubview(status)
        cropStatusLabel = status

        cropWindow = window
        refreshCropTunerFields()
        refreshCropPreview()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === cropWindow {
            cropWindow = nil
            cropPreviewView = nil
            cropFrameImageView = nil
            cropValueFields.removeAll()
            cropSteppers.removeAll()
            cropStatusLabel = nil
        }
    }

    @objc private func openFramesFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: framesPath))
    }

    @objc private func openPluginFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: pluginPath).deletingLastPathComponent())
    }

    @objc private func openConfigFile() {
        ensureConfigDirectory()
        if !FileManager.default.fileExists(atPath: configPath) {
            writeCaptureConfig(readCaptureConfig())
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func cropControlChanged(_ sender: NSControl) {
        guard let key = sender.identifier?.rawValue else {
            return
        }

        let value: Double
        if let stepper = sender as? NSStepper {
            value = stepper.doubleValue
            cropValueFields[key]?.doubleValue = value
        } else if let field = sender as? NSTextField {
            value = field.doubleValue
            cropSteppers[key]?.doubleValue = value
        } else {
            return
        }

        var config = readCaptureConfig()
        switch key {
        case "x":
            config.cropX = max(0, value)
        case "y":
            config.cropY = max(0, value)
        case "width":
            config.cropWidth = max(8, value)
        case "height":
            config.cropHeight = max(8, value)
        default:
            return
        }
        writeCaptureConfig(config)
        refreshCropTunerFields()
        cropPreviewView?.crop = cropRect(from: config)
        refreshCropPreview()
    }

    @objc private func saveCropAndRestart() {
        restartHelper()
        cropStatusLabel?.stringValue = "Saved crop and restarted helper."
    }

    @objc private func resetCropFromTuner() {
        var config = readCaptureConfig()
        config.cropX = 248
        config.cropY = 222
        config.cropWidth = 89
        config.cropHeight = 89
        writeCaptureConfig(config)
        refreshCropTunerFields()
        cropPreviewView?.crop = cropRect(from: config)
        refreshCropPreview()
    }

    @objc private func requestScreenRecordingPermission() {
        let helperAppPath = helperAppPath
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [
                "-n",
                helperAppPath,
                "--args",
                "--request-screen-recording-access"
            ]
            try? process.run()
        }
        cropStatusLabel?.stringValue = "Requested Screen Recording permission for Codex Pet Capture."
    }

    @objc private func refreshCropPreview() {
        let config = readCaptureConfig()
        let helperAppPath = helperAppPath
        let framesPath = framesPath
        let arguments = [
            "-W",
            "-n",
            helperAppPath,
            "--args",
            "--crop-preview-best",
            "--frame-mode",
            config.frameMode,
            "--crop-x",
            formatConfigNumber(config.cropX),
            "--crop-y",
            formatConfigNumber(config.cropY),
            "--crop-width",
            formatConfigNumber(config.cropWidth),
            "--crop-height",
            formatConfigNumber(config.cropHeight),
            "--output-dir",
            framesPath
        ]
        cropStatusLabel?.stringValue = "Rendering preview..."

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = arguments

            do {
                try process.run()
                process.waitUntilExit()
                let exitCode = process.terminationStatus
                DispatchQueue.main.async {
                    let loaded = self.loadCropPreviewImages()
                    self.cropStatusLabel?.stringValue = exitCode == 0 && loaded
                        ? "Preview updated. Use Save & Restart Helper to apply to live capture."
                        : "Preview image was not generated. Check Screen Recording permission for Codex Pet Capture."
                }
            } catch {
                DispatchQueue.main.async {
                    self.cropStatusLabel?.stringValue = "Preview failed: \(error)"
                }
            }
        }
    }

    private func showStatus(status: String, message: String) {
        statusLine.title = "Helper: \(status)"
        frameLine.title = "Frame: unknown"
        windowLine.title = "Window: unknown"
        configLine.title = configSummary(readCaptureConfig())
        messageLine.title = message.isEmpty ? "No details." : message
        applyMenuBarIcon(hasIssue: true)
    }

    private func applyCropFromPreview(_ crop: CGRect, refreshFrame: Bool) {
        var config = readCaptureConfig()
        config.cropX = Double(crop.minX)
        config.cropY = Double(crop.minY)
        config.cropWidth = Double(crop.width)
        config.cropHeight = Double(crop.height)
        writeCaptureConfig(config)
        refreshCropTunerFields()

        if refreshFrame {
            refreshCropPreview()
        } else {
            cropStatusLabel?.stringValue = "Adjusting crop..."
        }
    }

    private func makeLabel(_ title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func addCropControl(key: String, title: String, y: CGFloat, to content: NSView) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 418, y: y + 5, width: 58, height: 20)
        content.addSubview(label)

        let field = NSTextField(frame: NSRect(x: 480, y: y, width: 78, height: 28))
        field.identifier = NSUserInterfaceItemIdentifier(key)
        field.target = self
        field.action = #selector(cropControlChanged(_:))
        field.alignment = .right
        content.addSubview(field)
        cropValueFields[key] = field

        let stepper = NSStepper(frame: NSRect(x: 566, y: y, width: 24, height: 28))
        stepper.identifier = NSUserInterfaceItemIdentifier(key)
        stepper.target = self
        stepper.action = #selector(cropControlChanged(_:))
        stepper.minValue = key == "width" || key == "height" ? 8 : 0
        stepper.maxValue = 600
        stepper.increment = 1
        content.addSubview(stepper)
        cropSteppers[key] = stepper
    }

    private func refreshCropTunerFields() {
        let config = readCaptureConfig()
        setCropTunerValue(key: "x", value: config.cropX)
        setCropTunerValue(key: "y", value: config.cropY)
        setCropTunerValue(key: "width", value: config.cropWidth)
        setCropTunerValue(key: "height", value: config.cropHeight)
        cropPreviewView?.crop = cropRect(from: config)
    }

    private func setCropTunerValue(key: String, value: Double) {
        cropValueFields[key]?.stringValue = formatConfigNumber(value)
        cropSteppers[key]?.doubleValue = value
    }

    @discardableResult
    private func loadCropPreviewImages() -> Bool {
        let sourcePath = "\(framesPath)/crop-source.png"
        let previewPath = "\(framesPath)/crop-preview.png"
        let framePath = "\(framesPath)/crop-frame.png"
        guard let sourceImage = NSImage(contentsOfFile: sourcePath) ?? NSImage(contentsOfFile: previewPath),
              let frameImage = NSImage(contentsOfFile: framePath) else {
            return false
        }

        cropPreviewView?.image = sourceImage
        cropPreviewView?.crop = cropRect(from: readCaptureConfig())
        cropFrameImageView?.image = frameImage
        return true
    }

    private func cropRect(from config: CaptureConfig) -> CGRect {
        CGRect(
            x: config.cropX,
            y: config.cropY,
            width: config.cropWidth,
            height: config.cropHeight
        )
    }

    private func configSummary(_ config: CaptureConfig) -> String {
        if config.helperMode == "capture-overlay" {
            return "Config: capture-overlay, fps \(formatFPS(config.fps)), crop \(formatConfigNumber(config.cropX)),\(formatConfigNumber(config.cropY)) \(formatConfigNumber(config.cropWidth))x\(formatConfigNumber(config.cropHeight))"
        }

        let state = config.petState.isEmpty ? "auto" : config.petState
        return "Config: render-assets, fps \(formatFPS(config.fps)), state \(state)"
    }

    private func formatFPS(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.2f", value)
    }

    private func updateFPSMenu() {
        let currentFPS = readCaptureConfig().fps
        for item in fpsMenuItems {
            guard let fps = item.representedObject as? Double else {
                item.state = .off
                continue
            }
            item.state = abs(fps - currentFPS) < 0.001 ? .on : .off
        }
    }

    private func readCaptureConfig() -> CaptureConfig {
        var config = CaptureConfig()
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return config
        }

        for rawLine in content.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else {
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            switch key {
            case "FPS":
                config.fps = Double(value) ?? config.fps
            case "RETRY_INTERVAL":
                config.retryInterval = Double(value) ?? config.retryInterval
            case "HELPER_MODE":
                config.helperMode = value
            case "PET_ID":
                config.petID = value
            case "PET_STATE":
                config.petState = value
            case "FRAME_MODE":
                config.frameMode = value
            case "CAPTURE_ENGINE":
                config.captureEngine = value
            case "CROP_X":
                config.cropX = Double(value) ?? config.cropX
            case "CROP_Y":
                config.cropY = Double(value) ?? config.cropY
            case "CROP_WIDTH":
                config.cropWidth = Double(value) ?? config.cropWidth
            case "CROP_HEIGHT":
                config.cropHeight = Double(value) ?? config.cropHeight
            default:
                continue
            }
        }

        config.fps = min(max(config.fps, 1), 15)
        config.retryInterval = max(config.retryInterval, 0.25)
        if config.helperMode != "render-assets" && config.helperMode != "capture-overlay" {
            config.helperMode = "render-assets"
        }
        config.cropX = max(config.cropX, 0)
        config.cropY = max(config.cropY, 0)
        config.cropWidth = max(config.cropWidth, 8)
        config.cropHeight = max(config.cropHeight, 8)
        return config
    }

    private func writeCaptureConfig(_ config: CaptureConfig) {
        ensureConfigDirectory()
        let content = """
        FPS="\(formatConfigNumber(config.fps))"
        RETRY_INTERVAL="\(formatConfigNumber(config.retryInterval))"
        HELPER_MODE="\(config.helperMode)"
        PET_ID="\(config.petID)"
        PET_STATE="\(config.petState)"
        FRAME_MODE="\(config.frameMode)"
        CAPTURE_ENGINE="\(config.captureEngine)"
        CROP_X="\(formatConfigNumber(config.cropX))"
        CROP_Y="\(formatConfigNumber(config.cropY))"
        CROP_WIDTH="\(formatConfigNumber(config.cropWidth))"
        CROP_HEIGHT="\(formatConfigNumber(config.cropHeight))"
        """

        do {
            try content.write(toFile: configPath, atomically: true, encoding: .utf8)
        } catch {
            showStatus(status: "config-write-failed", message: String(describing: error))
        }
    }

    private func ensureConfigDirectory() {
        let directory = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func formatConfigNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.2f", value)
    }

    private func applyMenuBarIcon(hasIssue: Bool) {
        statusItem.button?.image = makeMenuBarIcon(hasIssue: hasIssue)
        statusItem.button?.toolTip = hasIssue
            ? "Codex Pet Stream Deck needs attention"
            : "Codex Pet Stream Deck"
    }

    private func makeMenuBarIcon(hasIssue: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            let symbolColor = NSColor.labelColor
            let accentColor = hasIssue ? NSColor.systemRed : NSColor.systemGreen

            if let displaySymbol = NSImage(
                systemSymbolName: "display",
                accessibilityDescription: "Codex Pet Stream Deck"
            )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)) {
                symbolColor.setFill()
                displaySymbol.draw(
                    in: NSRect(x: 1.2, y: 1.5, width: 16.2, height: 15.2),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            } else {
                symbolColor.withAlphaComponent(0.95).setStroke()
                let display = NSBezierPath(
                    roundedRect: NSRect(x: 2.4, y: 4, width: 13.6, height: 9.8),
                    xRadius: 2.4,
                    yRadius: 2.4
                )
                display.lineWidth = 1.7
                display.stroke()

                let stand = NSBezierPath()
                stand.move(to: NSPoint(x: 7.2, y: 4))
                stand.line(to: NSPoint(x: 6.3, y: 2.4))
                stand.move(to: NSPoint(x: 11.1, y: 4))
                stand.line(to: NSPoint(x: 12, y: 2.4))
                stand.move(to: NSPoint(x: 5.8, y: 2.4))
                stand.line(to: NSPoint(x: 12.5, y: 2.4))
                stand.lineWidth = 1.4
                stand.stroke()
            }

            accentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 13.2, y: 10.2, width: 5.7, height: 5.7)).fill()
            if hasIssue {
                NSColor.white.setFill()
                NSBezierPath(roundedRect: NSRect(x: 15.65, y: 12.2, width: 0.8, height: 2.1), xRadius: 0.4, yRadius: 0.4).fill()
                NSBezierPath(ovalIn: NSRect(x: 15.45, y: 11, width: 1.2, height: 1.2)).fill()
            }

            return true
        }
        image.isTemplate = false
        return image
    }

    private func isHelperLoaded() -> Bool {
        runLaunchctl(arguments: ["print", "gui/\(getuid())/\(helperLabel)"]).exitCode == 0
    }

    private func readFrameStatus() -> FrameStatus? {
        guard let data = FileManager.default.contents(atPath: statusPath) else {
            return nil
        }

        return try? JSONDecoder().decode(FrameStatus.self, from: data)
    }

    private func runLaunchctl(arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, String(describing: error))
        }
    }

    private func terminateCaptureProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-f", "codex-pet-capture"]
        try? process.run()
        process.waitUntilExit()
    }
}

let app = NSApplication.shared
let delegate = MenuBarController()
app.delegate = delegate
app.run()

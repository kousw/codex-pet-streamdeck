import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum PetAnimationState: String, Codable, CaseIterable {
    case idle
    case running
    case waiting
    case failed
    case review
}

struct AssetRenderStatus: Codable {
    let version: Int
    let status: String
    let source: String
    let stateSource: String?
    let updatedAt: String
    let framePath: String?
    let frameSequence: Int?
    let frameSlot: Int?
    let frameDataPath: String?
    let captureMode: String?
    let captureFPS: Double?
    let renderFPS: Double?
    let crop: CropConfiguration?
    let targetWindowID: UInt32?
    let petID: String?
    let petState: PetAnimationState?
    let notificationBadgeCount: Int?
    let message: String?
}

struct PetManifest: Decodable {
    let id: String
    let displayName: String?
    let spritesheetPath: String?
}

struct ResolvedPet {
    let id: String
    let directory: URL
    let spritesheetURL: URL
}

final class AssetRenderService {
    private let fps: Double
    private let retryIntervalSeconds: Double
    private let outputDirectory: URL
    private let durationSeconds: Double?
    private let explicitPetID: String?
    private let explicitPetState: PetAnimationState?
    private let debugLogging: Bool
    private let petResolver = PetResolver()
    private let stateResolver = CodexActivityStateResolver()
    private let spriteRenderer = SpriteSheetFrameRenderer()
    private let imageWriter = ImageWriter()
    private let statusWriter = StatusWriter()
    private let slotCount = 8
    private var animationKey: String?
    private var animationStartedAt = Date()

    init(
        fps: Double,
        retryIntervalSeconds: Double,
        outputDirectory: String,
        durationSeconds: Double?,
        petID: String?,
        petState: PetAnimationState?,
        debugLogging: Bool = false
    ) {
        self.fps = fps
        self.retryIntervalSeconds = retryIntervalSeconds
        self.outputDirectory = URL(fileURLWithPath: outputDirectory)
        self.durationSeconds = durationSeconds
        self.explicitPetID = petID
        self.explicitPetState = petState
        self.debugLogging = debugLogging
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

            do {
                let pet = try petResolver.resolve(preferredID: explicitPetID)
                let stateResult = stateResolver.resolve(explicitState: explicitPetState)
                try publishFrame(pet: pet, stateResult: stateResult, sequence: sequence)
                sequence += 1
                try await Task.sleep(nanoseconds: frameIntervalNanoseconds)
            } catch {
                try writeStatus(
                    status: "render-failed",
                    message: String(describing: error)
                )
                try await Task.sleep(nanoseconds: retryIntervalNanoseconds)
            }
        }
    }

    private func publishFrame(
        pet: ResolvedPet,
        stateResult: CodexActivityStateResult,
        sequence: Int
    ) throws {
        let elapsedSeconds = animationElapsedSeconds(pet: pet, state: stateResult.state)
        let renderedFrame = if let override = stateResult.spriteFrameOverride {
            try spriteRenderer.renderFrame(
                spritesheetURL: pet.spritesheetURL,
                spriteFrame: SpriteTimelineFrame(row: override.row, column: override.column, durationMilliseconds: 0),
                notificationBadgeCount: stateResult.notificationBadgeCount
            )
        } else {
            try spriteRenderer.renderFrame(
                spritesheetURL: pet.spritesheetURL,
                state: stateResult.state,
                elapsedSeconds: elapsedSeconds,
                notificationBadgeCount: stateResult.notificationBadgeCount
            )
        }
        let slot = sequence % slotCount
        let latestPath = outputDirectory.appendingPathComponent("latest.png")
        let statusPath = outputDirectory.appendingPathComponent("status.json")
        let dataURLPath = outputDirectory.appendingPathComponent("latest-data-url.txt")
        let slotPath = outputDirectory.appendingPathComponent("frame-\(slot).png")
        let pngData = try imageWriter.pngData(renderedFrame.image)

        try AtomicFileWriter.writePNG(renderedFrame.image, to: slotPath, imageWriter: imageWriter)
        try AtomicFileWriter.writePNG(renderedFrame.image, to: latestPath, imageWriter: imageWriter)
        try AtomicFileWriter.writeText(dataURL(forPNGData: pngData), to: dataURLPath)

        let status = AssetRenderStatus(
            version: 2,
            status: "ok",
            source: "asset-renderer",
            stateSource: stateResult.source,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            framePath: slotPath.path,
            frameSequence: sequence,
            frameSlot: slot,
            frameDataPath: dataURLPath.path,
            captureMode: "render-assets",
            captureFPS: fps,
            renderFPS: fps,
            crop: nil,
            targetWindowID: nil,
            petID: pet.id,
            petState: stateResult.state,
            notificationBadgeCount: stateResult.notificationBadgeCount,
            message: nil
        )
        try AtomicFileWriter.writeJSON(status, to: statusPath, statusWriter: statusWriter)

        debug(
            "render frame \(sequence) slot=\(slot) pet=\(pet.id) state=\(stateResult.state.rawValue) source=\(stateResult.source) sprite=row:\(renderedFrame.sprite.row),col:\(renderedFrame.sprite.column) badge=\(stateResult.notificationBadgeCount ?? 0) elapsedMs=\(Int((elapsedSeconds * 1000).rounded(.down))) -> \(slotPath.path)"
        )
    }

    private func animationElapsedSeconds(pet: ResolvedPet, state: PetAnimationState) -> TimeInterval {
        let key = "\(pet.id):\(state.rawValue)"
        let now = Date()
        if animationKey != key {
            animationKey = key
            animationStartedAt = now
        }
        return now.timeIntervalSince(animationStartedAt)
    }

    private func writeStatus(
        status: String,
        petID: String? = nil,
        petState: PetAnimationState? = nil,
        stateSource: String? = nil,
        message: String
    ) throws {
        let statusPath = outputDirectory.appendingPathComponent("status.json")
        let value = AssetRenderStatus(
            version: 2,
            status: status,
            source: "asset-renderer",
            stateSource: stateSource,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            framePath: nil,
            frameSequence: nil,
            frameSlot: nil,
            frameDataPath: nil,
            captureMode: "render-assets",
            captureFPS: fps,
            renderFPS: fps,
            crop: nil,
            targetWindowID: nil,
            petID: petID,
            petState: petState,
            notificationBadgeCount: nil,
            message: message
        )
        try AtomicFileWriter.writeJSON(value, to: statusPath, statusWriter: statusWriter)
        print("\(status): \(message)")
        fflush(stdout)
    }

    private func debug(_ message: String) {
        guard debugLogging else {
            return
        }
        print(message)
        fflush(stdout)
    }

    private func dataURL(forPNGData data: Data) -> String {
        "data:image/png;base64,\(data.base64EncodedString())"
    }
}

enum PetResolverError: Error, CustomStringConvertible {
    case codexHomeNotFound
    case petNotFound(String?)
    case invalidManifest(URL)
    case missingSpritesheet(URL)

    var description: String {
        switch self {
        case .codexHomeNotFound:
            return "Could not resolve the Codex home directory."
        case let .petNotFound(id):
            return "No Codex custom pet found\(id.map { " for \($0)" } ?? "")."
        case let .invalidManifest(url):
            return "Invalid pet manifest at \(url.path)."
        case let .missingSpritesheet(url):
            return "Missing spritesheet at \(url.path)."
        }
    }
}

final class PetResolver {
    private let fileManager = FileManager.default

    func resolve(preferredID: String?) throws -> ResolvedPet {
        let codexHome = codexHomeURL()
        let petsDirectory = codexHome.appendingPathComponent("pets", isDirectory: true)
        let hasExplicitID = preferredID != nil
        let selectedID = preferredID ?? overridePetID(codexHome: codexHome) ?? persistedCustomPetID(codexHome: codexHome)

        if let selectedID {
            let normalizedID = normalizePetID(selectedID)
            if let pet = try resolveCustomPet(id: normalizedID, petsDirectory: petsDirectory) {
                return pet
            }
            if hasExplicitID {
                throw PetResolverError.petNotFound(selectedID)
            }
        }

        let petDirectories = ((try? fileManager.contentsOfDirectory(
            at: petsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { isDirectory($0) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for directory in petDirectories {
            if let pet = try resolveCustomPet(id: directory.lastPathComponent, petsDirectory: petsDirectory) {
                return pet
            }
        }

        throw PetResolverError.petNotFound(nil)
    }

    private func resolveCustomPet(id: String, petsDirectory: URL) throws -> ResolvedPet? {
        let directory = petsDirectory.appendingPathComponent(id, isDirectory: true)
        let manifestURL = directory.appendingPathComponent("pet.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let manifest: PetManifest
        do {
            let data = try Data(contentsOf: manifestURL)
            manifest = try JSONDecoder().decode(PetManifest.self, from: data)
        } catch {
            throw PetResolverError.invalidManifest(manifestURL)
        }

        let spritesheetName = manifest.spritesheetPath ?? "spritesheet.webp"
        let spritesheetURL = directory.appendingPathComponent(spritesheetName)
        guard fileManager.fileExists(atPath: spritesheetURL.path) else {
            throw PetResolverError.missingSpritesheet(spritesheetURL)
        }

        let petID = manifest.id.isEmpty ? id : manifest.id
        return ResolvedPet(id: "custom:\(petID)", directory: directory, spritesheetURL: spritesheetURL)
    }

    private func persistedCustomPetID(codexHome: URL) -> String? {
        let stateURL = codexHome.appendingPathComponent(".codex-global-state.json")
        guard
            let data = try? Data(contentsOf: stateURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let persisted = json["electron-persisted-atom-state"] as? [String: Any]
        else {
            return nil
        }

        for (key, value) in persisted where key.lowercased().contains("pet") || key.lowercased().contains("avatar") {
            if let string = value as? String, string.hasPrefix("custom:") {
                return string
            }
            if let strings = value as? [String], let custom = strings.first(where: { $0.hasPrefix("custom:") }) {
                return custom
            }
        }

        return nil
    }

    private func overridePetID(codexHome: URL) -> String? {
        let url = codexHome.appendingPathComponent("pet-streamdeck-state.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let petID = json["petId"] as? String,
            !petID.isEmpty
        else {
            return nil
        }
        return petID
    }

    private func normalizePetID(_ value: String) -> String {
        value.hasPrefix("custom:") ? String(value.dropFirst("custom:".count)) : value
    }

    private func codexHomeURL() -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

struct CodexActivityStateResult {
    let state: PetAnimationState
    let source: String
    let spriteFrameOverride: SpriteFrameOverride?
    let notificationBadgeCount: Int?
}

struct SpriteFrameOverride {
    let row: Int
    let column: Int
}

final class CodexActivityStateResolver {
    func resolve(explicitState: PetAnimationState?) -> CodexActivityStateResult {
        if let explicitState {
            return CodexActivityStateResult(
                state: explicitState,
                source: "cli",
                spriteFrameOverride: nil,
                notificationBadgeCount: nil
            )
        }

        if let override = overrideState() {
            return override
        }

        if let inferred = inferFromRecentSession() {
            return inferred
        }

        return CodexActivityStateResult(
            state: .idle,
            source: "default",
            spriteFrameOverride: nil,
            notificationBadgeCount: nil
        )
    }

    private func overrideState() -> CodexActivityStateResult? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/pet-streamdeck-state.json")
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let frameOverride = freshSpriteFrameOverride(from: json)
        let state = (json["state"] as? String).flatMap(PetAnimationState.init(rawValue:))
            ?? frameOverride.map { stateForSpriteRow($0.row) }

        guard let state else {
            return nil
        }
        return CodexActivityStateResult(
            state: state,
            source: frameOverride == nil ? "override-file" : "codex-debug-overlay",
            spriteFrameOverride: frameOverride,
            notificationBadgeCount: freshNotificationBadgeCount(from: json)
        )
    }

    private func inferFromRecentSession() -> CodexActivityStateResult? {
        let sessionsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let session = newestJSONLFile(in: sessionsDirectory) else {
            return nil
        }
        guard let tail = try? readTail(of: session, maxBytes: 128 * 1024).lowercased() else {
            return nil
        }

        for line in tail.split(separator: "\n").reversed() {
            let event = String(line)
            if event.contains("\"type\":\"event_msg\"") && event.contains("\"type\":\"error\"") {
                return CodexActivityStateResult(state: .failed, source: "codex-session", spriteFrameOverride: nil, notificationBadgeCount: nil)
            }
            if event.contains("approval_request") || event.contains("request_user_input") {
                return CodexActivityStateResult(state: .waiting, source: "codex-session", spriteFrameOverride: nil, notificationBadgeCount: nil)
            }
            if event.contains("\"type\":\"task_complete\"") || event.contains("\"phase\":\"final_answer\"") {
                return CodexActivityStateResult(state: .review, source: "codex-session", spriteFrameOverride: nil, notificationBadgeCount: nil)
            }
            if event.contains("\"type\":\"task_started\"") || event.contains("\"type\":\"function_call\"") {
                return CodexActivityStateResult(state: .running, source: "codex-session", spriteFrameOverride: nil, notificationBadgeCount: nil)
            }
        }

        return CodexActivityStateResult(state: .idle, source: "codex-session", spriteFrameOverride: nil, notificationBadgeCount: nil)
    }

    private func freshSpriteFrameOverride(from json: [String: Any]) -> SpriteFrameOverride? {
        guard
            let source = json["source"] as? String,
            source == "codex-debug-overlay",
            let updatedAt = json["updatedAt"] as? String,
            let updatedDate = parseISO8601Date(updatedAt),
            Date().timeIntervalSince(updatedDate) < 2,
            let row = json["spriteRow"] as? Int,
            let column = json["spriteColumn"] as? Int,
            (0..<9).contains(row),
            (0..<8).contains(column)
        else {
            return nil
        }
        return SpriteFrameOverride(row: row, column: column)
    }

    private func freshNotificationBadgeCount(from json: [String: Any]) -> Int? {
        guard freshSpriteFrameOverride(from: json) != nil else {
            return nil
        }
        guard let count = json["notificationBadgeCount"] as? Int, count > 0 else {
            return nil
        }
        return count
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func stateForSpriteRow(_ row: Int) -> PetAnimationState {
        switch row {
        case 5:
            return .failed
        case 6:
            return .waiting
        case 7:
            return .running
        case 8:
            return .review
        default:
            return .idle
        }
    }

    private func newestJSONLFile(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let date = values?.contentModificationDate else {
                continue
            }
            if newest == nil || date > newest!.date {
                newest = (url, date)
            }
        }
        return newest?.url
    }

    private func readTail(of url: URL, maxBytes: UInt64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > maxBytes ? size - maxBytes : 0
        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

enum SpriteSheetRendererError: Error, CustomStringConvertible {
    case couldNotLoadSpritesheet(URL)
    case invalidSpritesheetSize(Int, Int)
    case couldNotCropFrame
    case couldNotCreateContext
    case couldNotCreateFrame

    var description: String {
        switch self {
        case let .couldNotLoadSpritesheet(url):
            return "Could not load spritesheet at \(url.path)."
        case let .invalidSpritesheetSize(width, height):
            return "Invalid spritesheet size \(width)x\(height)."
        case .couldNotCropFrame:
            return "Could not crop spritesheet frame."
        case .couldNotCreateContext:
            return "Could not create render context."
        case .couldNotCreateFrame:
            return "Could not create rendered frame."
        }
    }
}

final class SpriteSheetFrameRenderer {
    private let outputSize = 144
    private let columns = 8
    private let rows = 9

    private let timeline = CodexAvatarAnimationTimeline()

    func renderFrame(
        spritesheetURL: URL,
        state: PetAnimationState,
        elapsedSeconds: TimeInterval,
        notificationBadgeCount: Int?
    ) throws -> RenderedSpriteFrame {
        try renderFrame(
            spritesheetURL: spritesheetURL,
            spriteFrame: timeline.frame(for: state, elapsedSeconds: elapsedSeconds),
            notificationBadgeCount: notificationBadgeCount
        )
    }

    func renderFrame(
        spritesheetURL: URL,
        spriteFrame: SpriteTimelineFrame,
        notificationBadgeCount: Int?
    ) throws -> RenderedSpriteFrame {
        let spritesheet = try loadImage(from: spritesheetURL)
        guard spritesheet.width % columns == 0, spritesheet.height % rows == 0 else {
            throw SpriteSheetRendererError.invalidSpritesheetSize(spritesheet.width, spritesheet.height)
        }

        let frameWidth = spritesheet.width / columns
        let frameHeight = spritesheet.height / rows
        let crop = CGRect(
            x: spriteFrame.column * frameWidth,
            y: spriteFrame.row * frameHeight,
            width: frameWidth,
            height: frameHeight
        )
        guard let frame = spritesheet.cropping(to: crop) else {
            throw SpriteSheetRendererError.couldNotCropFrame
        }
        return RenderedSpriteFrame(
            image: try renderCanvas(frame, canvasWidth: outputSize, canvasHeight: outputSize, notificationBadgeCount: notificationBadgeCount),
            sprite: spriteFrame
        )
    }

    private func loadImage(from url: URL) throws -> CGImage {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw SpriteSheetRendererError.couldNotLoadSpritesheet(url)
        }
        return image
    }

    private func renderCanvas(
        _ image: CGImage,
        canvasWidth: Int,
        canvasHeight: Int,
        notificationBadgeCount: Int?
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SpriteSheetRendererError.couldNotCreateContext
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = min(CGFloat(canvasWidth) / imageWidth, CGFloat(canvasHeight) / imageHeight)
        let drawWidth = floor(imageWidth * scale)
        let drawHeight = floor(imageHeight * scale)
        let drawRect = CGRect(
            x: floor((CGFloat(canvasWidth) - drawWidth) / 2),
            y: floor((CGFloat(canvasHeight) - drawHeight) / 2),
            width: drawWidth,
            height: drawHeight
        )

        context.draw(image, in: drawRect)

        if let notificationBadgeCount, notificationBadgeCount > 0 {
            drawBadge(count: notificationBadgeCount, in: context, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
        }

        guard let frame = context.makeImage() else {
            throw SpriteSheetRendererError.couldNotCreateFrame
        }
        return frame
    }

    private func drawBadge(count: Int, in context: CGContext, canvasWidth: Int, canvasHeight: Int) {
        let diameter: CGFloat = 34
        let rect = CGRect(
            x: CGFloat(canvasWidth) - diameter - 10,
            y: CGFloat(canvasHeight) - diameter - 8,
            width: diameter,
            height: diameter
        )

        context.setFillColor(CGColor(red: 0.91, green: 0.95, blue: 1.0, alpha: 1.0))
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(red: 0.78, green: 0.86, blue: 0.98, alpha: 1.0))
        context.setLineWidth(2)
        context.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))

        let text = String(min(count, 99)) as CFString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("Helvetica Neue" as CFString, 18, nil),
            .foregroundColor: CGColor(red: 0.06, green: 0.09, blue: 0.18, alpha: 1.0)
        ]
        let attributed = CFAttributedStringCreate(nil, text, attributes as CFDictionary)
        guard let attributed else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let textX = rect.midX - bounds.width / 2 - bounds.minX
        let textY = rect.midY - bounds.height / 2 - bounds.minY - 1
        context.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, context)
    }
}

struct RenderedSpriteFrame {
    let image: CGImage
    let sprite: SpriteTimelineFrame
}

struct SpriteTimelineFrame {
    let row: Int
    let column: Int
    let durationMilliseconds: Int
}

struct CodexAvatarAnimationTimeline {
    private let idleFrames: [SpriteTimelineFrame] = [
        SpriteTimelineFrame(row: 0, column: 0, durationMilliseconds: 280 * 6),
        SpriteTimelineFrame(row: 0, column: 1, durationMilliseconds: 110 * 6),
        SpriteTimelineFrame(row: 0, column: 2, durationMilliseconds: 110 * 6),
        SpriteTimelineFrame(row: 0, column: 3, durationMilliseconds: 140 * 6),
        SpriteTimelineFrame(row: 0, column: 4, durationMilliseconds: 140 * 6),
        SpriteTimelineFrame(row: 0, column: 5, durationMilliseconds: 320 * 6)
    ]

    private let stateFrames: [PetAnimationState: [SpriteTimelineFrame]] = [
        .failed: makeFrames(row: 5, count: 8, durationMilliseconds: 140, lastDurationMilliseconds: 240),
        .idle: [
            SpriteTimelineFrame(row: 0, column: 0, durationMilliseconds: 280),
            SpriteTimelineFrame(row: 0, column: 1, durationMilliseconds: 110),
            SpriteTimelineFrame(row: 0, column: 2, durationMilliseconds: 110),
            SpriteTimelineFrame(row: 0, column: 3, durationMilliseconds: 140),
            SpriteTimelineFrame(row: 0, column: 4, durationMilliseconds: 140),
            SpriteTimelineFrame(row: 0, column: 5, durationMilliseconds: 320)
        ],
        .review: makeFrames(row: 8, count: 6, durationMilliseconds: 150, lastDurationMilliseconds: 280),
        .running: makeFrames(row: 7, count: 6, durationMilliseconds: 120, lastDurationMilliseconds: 220),
        .waiting: makeFrames(row: 6, count: 6, durationMilliseconds: 150, lastDurationMilliseconds: 260)
    ]

    func frame(for state: PetAnimationState, elapsedSeconds: TimeInterval) -> SpriteTimelineFrame {
        let elapsedMilliseconds = max(0, Int((elapsedSeconds * 1000).rounded(.down)))
        if state == .idle {
            return frame(in: idleFrames, elapsedMilliseconds: elapsedMilliseconds)
        }

        let introFrames = stateFrames[state] ?? idleFrames
        let introDuration = duration(of: introFrames) * 3
        if elapsedMilliseconds < introDuration {
            return frame(in: repeated(introFrames, count: 3), elapsedMilliseconds: elapsedMilliseconds)
        }

        return frame(
            in: idleFrames,
            elapsedMilliseconds: elapsedMilliseconds - introDuration
        )
    }

    private func frame(
        in frames: [SpriteTimelineFrame],
        elapsedMilliseconds: Int
    ) -> SpriteTimelineFrame {
        guard !frames.isEmpty else {
            return SpriteTimelineFrame(row: 0, column: 0, durationMilliseconds: 1000)
        }

        let totalDuration = duration(of: frames)
        var remaining = totalDuration > 0 ? elapsedMilliseconds % totalDuration : 0
        for frame in frames {
            if remaining < frame.durationMilliseconds {
                return frame
            }
            remaining -= frame.durationMilliseconds
        }
        return frames[0]
    }

    private func duration(of frames: [SpriteTimelineFrame]) -> Int {
        frames.reduce(0) { $0 + $1.durationMilliseconds }
    }

    private func repeated(_ frames: [SpriteTimelineFrame], count: Int) -> [SpriteTimelineFrame] {
        Array(repeating: frames, count: count).flatMap { $0 }
    }

    private static func makeFrames(
        row: Int,
        count: Int,
        durationMilliseconds: Int,
        lastDurationMilliseconds: Int
    ) -> [SpriteTimelineFrame] {
        (0..<count).map { column in
            SpriteTimelineFrame(
                row: row,
                column: column,
                durationMilliseconds: column == count - 1 ? lastDurationMilliseconds : durationMilliseconds
            )
        }
    }
}

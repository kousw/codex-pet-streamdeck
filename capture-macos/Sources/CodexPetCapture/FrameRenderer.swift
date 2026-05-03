import CoreGraphics
import Foundation

enum FrameRendererError: Error {
    case couldNotCreateContext
    case couldNotCreateFrame
    case couldNotCropPet
}

struct CropConfiguration: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    static let `default` = CropConfiguration(x: 248, y: 222, width: 89, height: 89)
}

final class FrameRenderer {
    private let outputSize = 144
    private let cropConfiguration: CropConfiguration

    init(cropConfiguration: CropConfiguration = .default) {
        self.cropConfiguration = cropConfiguration
    }

    func render(image: CGImage, mode: FrameMode) throws -> CGImage {
        switch mode {
        case .pet:
            let crop = petCropRect(for: image)
            guard let cropped = image.cropping(to: crop) else {
                throw FrameRendererError.couldNotCropPet
            }
            return try aspectFit(cropped, canvasWidth: outputSize, canvasHeight: outputSize)
        case .petWithBubble:
            return try aspectFit(image, canvasWidth: outputSize, canvasHeight: outputSize)
        case .debugWide:
            return image
        }
    }

    func renderCropPreview(image: CGImage) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FrameRendererError.couldNotCreateContext
        }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        let crop = petCropRect(for: image)
        context.setStrokeColor(CGColor(red: 1, green: 0.05, blue: 0.05, alpha: 1))
        context.setLineWidth(max(2, CGFloat(image.width) / 180))
        context.stroke(crop.insetBy(dx: 1, dy: 1))

        context.setFillColor(CGColor(red: 1, green: 0.05, blue: 0.05, alpha: 0.18))
        context.fill(crop)

        guard let preview = context.makeImage() else {
            throw FrameRendererError.couldNotCreateFrame
        }
        return preview
    }

    private func petCropRect(for image: CGImage) -> CGRect {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Codex overlay currently lays out the mascot at roughly 244,191,112,121
        // in a 356x320 overlay. Add padding so the contact shadow and badge survive.
        let referenceWidth: CGFloat = 356
        let referenceHeight: CGFloat = 320
        let scaleX = width / referenceWidth
        let scaleY = height / referenceHeight

        let x = max(0, CGFloat(cropConfiguration.x) * scaleX)
        let y = max(0, CGFloat(cropConfiguration.y) * scaleY)
        let cropWidth = min(width - x, CGFloat(cropConfiguration.width) * scaleX)
        let cropHeight = min(height - y, CGFloat(cropConfiguration.height) * scaleY)

        return CGRect(x: x, y: y, width: cropWidth, height: cropHeight).integral
    }

    private func aspectFit(_ image: CGImage, canvasWidth: Int, canvasHeight: Int) throws -> CGImage {
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
            throw FrameRendererError.couldNotCreateContext
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false)

        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let scale = min(CGFloat(canvasWidth) / imageWidth, CGFloat(canvasHeight) / imageHeight)
        let drawWidth = imageWidth * scale
        let drawHeight = imageHeight * scale
        let drawRect = CGRect(
            x: floor((CGFloat(canvasWidth) - drawWidth) / 2),
            y: floor((CGFloat(canvasHeight) - drawHeight) / 2),
            width: floor(drawWidth),
            height: floor(drawHeight)
        )

        context.draw(image, in: drawRect)

        guard let frame = context.makeImage() else {
            throw FrameRendererError.couldNotCreateFrame
        }
        return frame
    }
}

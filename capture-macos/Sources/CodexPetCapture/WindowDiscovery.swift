import AppKit
import CoreGraphics
import Foundation

struct WindowInfo: Codable {
    let windowID: UInt32
    let ownerPID: Int32
    let ownerName: String
    let bundleIdentifier: String?
    let title: String?
    let layer: Int
    let alpha: Double?
    let isOnscreen: Bool
    let bounds: WindowBounds
}

struct WindowBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

final class WindowDiscovery {
    private let targetBundleIdentifier: String

    init(targetBundleIdentifier: String) {
        self.targetBundleIdentifier = targetBundleIdentifier
    }

    func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap(makeWindowInfo)
            .filter { $0.bundleIdentifier == targetBundleIdentifier }
            .sorted { lhs, rhs in
                if lhs.layer != rhs.layer {
                    return lhs.layer < rhs.layer
                }
                return lhs.windowID < rhs.windowID
            }
    }

    private func makeWindowInfo(from dictionary: [String: Any]) -> WindowInfo? {
        guard
            let windowID = dictionary[kCGWindowNumber as String] as? UInt32,
            let ownerPID = dictionary[kCGWindowOwnerPID as String] as? Int32,
            let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
            let boundsDictionary = dictionary[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else {
            return nil
        }

        let application = NSRunningApplication(processIdentifier: ownerPID)
        let bundleIdentifier = application?.bundleIdentifier

        return WindowInfo(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bundleIdentifier: bundleIdentifier,
            title: dictionary[kCGWindowName as String] as? String,
            layer: dictionary[kCGWindowLayer as String] as? Int ?? 0,
            alpha: dictionary[kCGWindowAlpha as String] as? Double,
            isOnscreen: (dictionary[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            bounds: WindowBounds(
                x: bounds.origin.x,
                y: bounds.origin.y,
                width: bounds.size.width,
                height: bounds.size.height
            )
        )
    }
}

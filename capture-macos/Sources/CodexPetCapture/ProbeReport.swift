import Foundation

struct ProbeReport: Codable {
    let generatedAt: String
    let targetBundleIdentifier: String
    let screenRecordingAccess: ScreenRecordingAccess
    let windowCount: Int
    let windows: [WindowInfo]
}

struct ScreenRecordingAccess: Codable {
    let isGranted: Bool
}

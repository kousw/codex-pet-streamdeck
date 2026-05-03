import CoreGraphics

enum ScreenRecordingPermission {
    static func isGranted(requestIfMissing: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        if requestIfMissing {
            return CGRequestScreenCaptureAccess()
        }

        return false
    }
}

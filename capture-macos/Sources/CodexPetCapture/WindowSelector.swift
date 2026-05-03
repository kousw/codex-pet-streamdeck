import Foundation

enum WindowSelector {
    static func bestPetOverlayWindow(from windows: [WindowInfo]) -> WindowInfo? {
        windows
            .filter { $0.isOnscreen }
            .sorted { lhs, rhs in
                let lhsScore = score(lhs)
                let rhsScore = score(rhs)
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.windowID > rhs.windowID
            }
            .first
    }

    static func score(_ window: WindowInfo) -> Double {
        let area = window.bounds.width * window.bounds.height
        let isLikelyOverlay = window.layer > 0
        let isPetSized = area >= 20_000 && area <= 250_000
        let overlayBonus = isLikelyOverlay ? 10_000_000.0 : 0
        let petSizedBonus = isPetSized ? 5_000_000.0 : 0
        let compactBonus = max(0, 500_000.0 - area)
        return overlayBonus + petSizedBonus + compactBonus
    }
}

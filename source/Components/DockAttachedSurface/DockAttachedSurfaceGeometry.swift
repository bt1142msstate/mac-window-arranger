import AppKit

extension NSScreen {
    static func bestScreen(for frame: NSRect, fallback: NSScreen?) -> NSScreen? {
        let candidates = screens.map { screen in
            (screen: screen, area: screen.frame.intersection(frame).positiveArea)
        }
        let bestMatch = candidates.max { first, second in
            first.area < second.area
        }

        if let bestMatch, bestMatch.area > 0 {
            return bestMatch.screen
        }

        return fallback ?? main ?? screens.first
    }
}

extension NSRect {
    var positiveArea: CGFloat {
        guard width > 0, height > 0 else {
            return 0
        }

        return width * height
    }
}

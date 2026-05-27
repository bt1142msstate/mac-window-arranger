import Foundation

enum ResizePreset: String, CaseIterable, Identifiable {
    case fullHD
    case hd
    case mobile
    case tablet
    case square
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullHD: "1080p"
        case .hd: "720p"
        case .mobile: "Mobile"
        case .tablet: "Tablet"
        case .square: "Square"
        case .custom: "Custom"
        }
    }

    var detail: String {
        switch self {
        case .fullHD: "Presentation and screen capture friendly."
        case .hd: "Fast default for smaller browser and app windows."
        case .mobile: "Tall phone viewport for responsive checks."
        case .tablet: "Tablet viewport for layout checks."
        case .square: "Square canvas for social and design previews."
        case .custom: "Use exact dimensions."
        }
    }

    var symbolName: String {
        switch self {
        case .fullHD, .hd: "rectangle"
        case .mobile: "iphone"
        case .tablet: "ipad"
        case .square: "square"
        case .custom: "slider.horizontal.3"
        }
    }

    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .fullHD: (1920, 1080)
        case .hd: (1280, 720)
        case .mobile: (375, 812)
        case .tablet: (768, 1024)
        case .square: (1080, 1080)
        case .custom: nil
        }
    }
}

enum ResizeStatusKind {
    case neutral
    case success
    case warning
    case error
}

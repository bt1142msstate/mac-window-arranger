import ApplicationServices
import CoreGraphics
import Foundation

struct AppItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let isRunning: Bool

    init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        bundleURL: URL? = nil,
        isRunning: Bool = true
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.isRunning = isRunning
    }

    var statusLabel: String {
        isRunning ? "Running" : "Installed"
    }
}

struct WindowItem: Identifiable, Hashable {
    let id: String
    let appName: String
    let bundleIdentifier: String?
    let processIdentifier: pid_t
    let windowNumber: CGWindowID
    let windowIndex: Int
    let title: String
    let frame: CGRect

    var displayName: String {
        if title.isEmpty {
            return "\(appName) - Window \(windowIndex + 1)"
        }

        return "\(appName) - \(title)"
    }
}

enum WindowWorkflowMode: String, CaseIterable, Identifiable, Hashable {
    case resize
    case arrange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .resize: "Resize"
        case .arrange: "Arrange"
        }
    }

    var symbolName: String {
        switch self {
        case .resize: "aspectratio"
        case .arrange: "rectangle.3.group"
        }
    }

    var contentSize: CGSize {
        switch self {
        case .resize: CGSize(width: 760, height: 300)
        case .arrange: CGSize(width: 760, height: 500)
        }
    }
}

enum LayoutKind: String, CaseIterable, Identifiable, Codable {
    case twoColumns
    case threeColumns
    case fourGrid
    case focusStack
    case customPositions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoColumns: "Two Columns"
        case .threeColumns: "Three Columns"
        case .fourGrid: "Four Grid"
        case .focusStack: "Focus + Stack"
        case .customPositions: "Custom Positions"
        }
    }

    var detail: String {
        switch self {
        case .twoColumns:
            return "Two apps side by side."
        case .threeColumns:
            return "Three equal windows across the screen."
        case .fourGrid:
            return "Four windows in equal quadrants."
        case .focusStack:
            return "One large focus window with two stacked side windows."
        case .customPositions:
            return "Save the selected windows exactly where they are now."
        }
    }

    var symbolName: String {
        switch self {
        case .twoColumns: "rectangle.split.2x1"
        case .threeColumns: "rectangle.split.3x1"
        case .fourGrid: "rectangle.grid.2x2"
        case .focusStack: "rectangle.leadinghalf.inset.filled"
        case .customPositions: "slider.horizontal.3"
        }
    }

    var fixedWindowCount: Int? {
        switch self {
        case .twoColumns: 2
        case .threeColumns: 3
        case .fourGrid: 4
        case .focusStack: 3
        case .customPositions: nil
        }
    }

    var usesStoredFrames: Bool {
        self == .customPositions
    }

    func slotTitle(for index: Int) -> String {
        switch self {
        case .twoColumns:
            return index == 0 ? "Left" : "Right"
        case .threeColumns:
            switch index {
            case 0: return "Left"
            case 1: return "Center"
            default: return "Right"
            }
        case .fourGrid:
            switch index {
            case 0: return "Top Left"
            case 1: return "Top Right"
            case 2: return "Bottom Left"
            default: return "Bottom Right"
            }
        case .focusStack:
            switch index {
            case 0: return "Main"
            case 1: return "Side Top"
            default: return "Side Bottom"
            }
        case .customPositions:
            return "Window \(index + 1)"
        }
    }

    func previewFrames(slotCount: Int) -> [CGRect] {
        let count = max(slotCount, 1)

        switch self {
        case .twoColumns:
            return Self.columnPreviewFrames(count: 2)
        case .threeColumns:
            return Self.columnPreviewFrames(count: 3)
        case .fourGrid:
            return [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            ]
        case .focusStack:
            return [
                CGRect(x: 0, y: 0, width: 0.62, height: 1),
                CGRect(x: 0.62, y: 0, width: 0.38, height: 0.5),
                CGRect(x: 0.62, y: 0.5, width: 0.38, height: 0.5)
            ]
        case .customPositions:
            return Self.adaptivePreviewFrames(count: count)
        }
    }

    private static func columnPreviewFrames(count: Int) -> [CGRect] {
        let safeCount = max(count, 1)
        let width = 1 / CGFloat(safeCount)

        return (0..<safeCount).map { index in
            CGRect(x: CGFloat(index) * width, y: 0, width: width, height: 1)
        }
    }

    private static func adaptivePreviewFrames(count: Int) -> [CGRect] {
        switch count {
        case 1:
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case 2:
            return columnPreviewFrames(count: 2)
        case 3:
            return LayoutKind.focusStack.previewFrames(slotCount: 3)
        case 4:
            return LayoutKind.fourGrid.previewFrames(slotCount: 4)
        case 5...6:
            return gridPreviewFrames(count: count, columns: 3)
        default:
            return gridPreviewFrames(count: count, columns: 4)
        }
    }

    private static func gridPreviewFrames(count: Int, columns: Int) -> [CGRect] {
        let safeCount = max(count, 1)
        let safeColumns = max(columns, 1)
        let rows = Int(ceil(Double(safeCount) / Double(safeColumns)))
        let width = 1 / CGFloat(safeColumns)
        let height = 1 / CGFloat(max(rows, 1))

        return (0..<safeCount).map { index in
            let column = index % safeColumns
            let row = index / safeColumns

            return CGRect(
                x: CGFloat(column) * width,
                y: CGFloat(row) * height,
                width: width,
                height: height
            )
        }
    }
}

struct LayoutPreviewPane: Identifiable, Hashable {
    var id: Int { position }

    let position: Int
    let slotTitle: String
    let selectedWindowID: String?
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let frame: CGRect

    var hasWindow: Bool {
        appName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var primaryLabel: String {
        guard let appName, !appName.isEmpty else {
            return "Choose Window"
        }

        return appName
    }

    var secondaryLabel: String {
        guard let windowTitle, !windowTitle.isEmpty else {
            return slotTitle
        }

        return windowTitle
    }
}

struct NormalizedWindowFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(frame: CGRect, in visibleFrame: CGRect) {
        let safeWidth = max(visibleFrame.width, 1)
        let safeHeight = max(visibleFrame.height, 1)

        self.x = Double((frame.minX - visibleFrame.minX) / safeWidth)
        self.y = Double((frame.minY - visibleFrame.minY) / safeHeight)
        self.width = Double(frame.width / safeWidth)
        self.height = Double(frame.height / safeHeight)
    }

    func frame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.minX + (CGFloat(x) * visibleFrame.width),
            y: visibleFrame.minY + (CGFloat(y) * visibleFrame.height),
            width: CGFloat(width) * visibleFrame.width,
            height: CGFloat(height) * visibleFrame.height
        ).roundedForWindowManagement()
    }

    var previewFrame: CGRect {
        CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
        .clampedToUnitFrame()
    }
}

struct SavedLayout: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var layoutKind: LayoutKind
    var slots: [SavedLayoutSlot]
    var updatedAt: Date

    init(id: UUID, name: String, layoutKind: LayoutKind, slots: [SavedLayoutSlot], updatedAt: Date) {
        self.id = id
        self.name = name
        self.layoutKind = layoutKind
        self.slots = slots
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case layoutKind
        case slots
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        layoutKind = try container.decodeIfPresent(LayoutKind.self, forKey: .layoutKind) ?? .threeColumns
        slots = try container.decode([SavedLayoutSlot].self, forKey: .slots)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var previewPanes: [LayoutPreviewPane] {
        let orderedSlots = slots.sorted { $0.position < $1.position }
        let fallbackFrames = layoutKind.previewFrames(slotCount: orderedSlots.count)

        return orderedSlots.enumerated().map { offset, slot in
            let fallbackFrame = fallbackFrames[safe: slot.position] ?? fallbackFrames[safe: offset] ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let storedFrame = slot.normalizedFrame?.previewFrame
            let previewFrame = storedFrame?.isUsablePreviewFrame == true ? storedFrame ?? fallbackFrame : fallbackFrame

            return LayoutPreviewPane(
                position: slot.position,
                slotTitle: layoutKind.slotTitle(for: slot.position),
                selectedWindowID: nil,
                appName: slot.appName,
                bundleIdentifier: slot.bundleIdentifier,
                windowTitle: slot.windowTitle,
                frame: previewFrame
            )
        }
    }
}

struct SavedLayoutSlot: Identifiable, Codable, Hashable {
    var id: UUID
    var position: Int
    var appName: String
    var bundleIdentifier: String?
    var windowTitle: String
    var normalizedFrame: NormalizedWindowFrame?

    init(id: UUID, position: Int, appName: String, bundleIdentifier: String?, windowTitle: String, normalizedFrame: NormalizedWindowFrame?) {
        self.id = id
        self.position = position
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.normalizedFrame = normalizedFrame
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case position
        case appName
        case bundleIdentifier
        case windowTitle
        case normalizedFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(Int.self, forKey: .position)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        normalizedFrame = try container.decodeIfPresent(NormalizedWindowFrame.self, forKey: .normalizedFrame)
    }
}

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

private extension CGRect {
    var isUsablePreviewFrame: Bool {
        width >= 0.06 && height >= 0.06
    }

    func clampedToUnitFrame() -> CGRect {
        let x = min(max(minX, 0), 1)
        let y = min(max(minY, 0), 1)
        let maxX = min(max(maxX, 0), 1)
        let maxY = min(max(maxY, 0), 1)

        return CGRect(
            x: x,
            y: y,
            width: max(maxX - x, 0),
            height: max(maxY - y, 0)
        )
    }
}

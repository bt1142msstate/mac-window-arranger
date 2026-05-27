import CoreGraphics
import Foundation

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

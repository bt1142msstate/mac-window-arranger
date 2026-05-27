import CoreGraphics

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

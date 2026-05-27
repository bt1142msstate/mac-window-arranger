import CoreGraphics

struct WindowLayoutFrameService {
    func frames(for layoutKind: LayoutKind, in visibleFrame: CGRect) -> [CGRect] {
        switch layoutKind {
        case .twoColumns:
            return columnFrames(count: 2, in: visibleFrame)
        case .threeColumns:
            return columnFrames(count: 3, in: visibleFrame)
        case .fourGrid:
            return gridFrames(columns: 2, rows: 2, in: visibleFrame)
        case .focusStack:
            let mainWidth = floor(visibleFrame.width * 0.62)
            let sideWidth = visibleFrame.width - mainWidth
            let sideHeight = floor(visibleFrame.height / 2)

            return [
                CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: mainWidth, height: visibleFrame.height),
                CGRect(x: visibleFrame.minX + mainWidth, y: visibleFrame.minY, width: sideWidth, height: sideHeight),
                CGRect(x: visibleFrame.minX + mainWidth, y: visibleFrame.minY + sideHeight, width: sideWidth, height: visibleFrame.height - sideHeight)
            ].map { $0.roundedForWindowManagement() }
        case .customPositions:
            return []
        }
    }

    func nonOverlappingFrames(forVisibleWindowCount count: Int, in visibleFrame: CGRect) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        switch count {
        case 1:
            return [visibleFrame.roundedForWindowManagement()]
        case 2:
            return columnFrames(count: 2, in: visibleFrame)
        case 3:
            return frames(for: .focusStack, in: visibleFrame)
        case 4:
            return gridFrames(columns: 2, rows: 2, in: visibleFrame)
        default:
            let dimensions = adaptiveGridDimensions(for: count, in: visibleFrame)
            return Array(
                gridFrames(columns: dimensions.columns, rows: dimensions.rows, in: visibleFrame)
                    .prefix(count)
            )
        }
    }

    private func columnFrames(count: Int, in visibleFrame: CGRect) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        let baseWidth = floor(visibleFrame.width / CGFloat(count))
        var frames: [CGRect] = []
        var x = visibleFrame.minX

        for index in 0..<count {
            let width = index == count - 1
                ? visibleFrame.maxX - x
                : baseWidth

            frames.append(
                CGRect(
                    x: x,
                    y: visibleFrame.minY,
                    width: width,
                    height: visibleFrame.height
                ).roundedForWindowManagement()
            )
            x += width
        }

        return frames
    }

    private func gridFrames(columns: Int, rows: Int, in visibleFrame: CGRect) -> [CGRect] {
        guard columns > 0, rows > 0 else {
            return []
        }

        let baseWidth = floor(visibleFrame.width / CGFloat(columns))
        let baseHeight = floor(visibleFrame.height / CGFloat(rows))
        var frames: [CGRect] = []

        for row in 0..<rows {
            var x = visibleFrame.minX
            let height = row == rows - 1
                ? visibleFrame.maxY - (visibleFrame.minY + CGFloat(row) * baseHeight)
                : baseHeight

            for column in 0..<columns {
                let width = column == columns - 1
                    ? visibleFrame.maxX - x
                    : baseWidth

                frames.append(
                    CGRect(
                        x: x,
                        y: visibleFrame.minY + CGFloat(row) * baseHeight,
                        width: width,
                        height: height
                    ).roundedForWindowManagement()
                )
                x += width
            }
        }

        return frames
    }

    private func adaptiveGridDimensions(for count: Int, in visibleFrame: CGRect) -> (columns: Int, rows: Int) {
        let safeCount = max(count, 1)
        let aspectRatio = max(Double(visibleFrame.width / max(visibleFrame.height, 1)), 0.5)
        let columns = min(
            safeCount,
            max(1, Int(ceil(sqrt(Double(safeCount) * aspectRatio))))
        )
        let rows = max(1, Int(ceil(Double(safeCount) / Double(columns))))

        return (columns, rows)
    }
}

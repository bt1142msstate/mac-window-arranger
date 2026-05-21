import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let outputPath = arguments.first ?? "docs/assets/mac-window-resizer-preview.png"
let iconPath = arguments.dropFirst().first ?? "docs/assets/mac-window-resizer-icon.png"

let canvasSize = NSSize(width: 1600, height: 1000)
let image = NSImage(size: canvasSize)

func rectFromTop(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvasSize.height - y - height, width: width, height: height)
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func strokeRounded(_ rect: NSRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.lineWidth = lineWidth
    color.setStroke()
    path.stroke()
}

func drawText(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color textColor: NSColor = .white,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: textColor,
        .paragraphStyle: paragraph
    ]

    NSString(string: text).draw(
        in: rectFromTop(x: x, y: y, width: width, height: height),
        withAttributes: attributes
    )
}

func drawPill(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, fill: NSColor) {
    fillRounded(rectFromTop(x: x, y: y, width: width, height: 46), radius: 14, color: fill)
    drawText(text, x: x + 18, y: y + 12, width: width - 36, height: 22, size: 18, weight: .semibold)
}

func drawPanel(title: String, symbol: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
    let rect = rectFromTop(x: x, y: y, width: width, height: height)
    fillRounded(rect, radius: 18, color: color(0x242930))
    strokeRounded(rect, radius: 18, color: color(0x404853))
    drawText(symbol, x: x + 28, y: y + 26, width: 54, height: 26, size: 19, weight: .semibold, color: color(0x99a4b0))
    drawText(title.uppercased(), x: x + 86, y: y + 29, width: width - 114, height: 24, size: 15, weight: .bold, color: color(0xa9b2bd))
}

image.lockFocus()

fillRounded(rectFromTop(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height), radius: 0, color: color(0xf3f5f8))

let backgroundPath = NSBezierPath()
backgroundPath.move(to: NSPoint(x: 0, y: canvasSize.height))
backgroundPath.curve(
    to: NSPoint(x: canvasSize.width, y: 150),
    controlPoint1: NSPoint(x: 420, y: 860),
    controlPoint2: NSPoint(x: 1020, y: 120)
)
backgroundPath.line(to: NSPoint(x: canvasSize.width, y: canvasSize.height))
backgroundPath.close()
color(0xdce6f1).setFill()
backgroundPath.fill()

fillRounded(rectFromTop(x: 118, y: 120, width: 1236, height: 760), radius: 28, color: color(0x15191f))
fillRounded(rectFromTop(x: 118, y: 120, width: 1236, height: 78), radius: 28, color: color(0x242a31))
fillRounded(rectFromTop(x: 118, y: 166, width: 1236, height: 34), radius: 0, color: color(0x242a31))

fillRounded(rectFromTop(x: 150, y: 148, width: 22, height: 22), radius: 11, color: color(0xff5f57))
fillRounded(rectFromTop(x: 190, y: 148, width: 22, height: 22), radius: 11, color: color(0xffbd2e))
fillRounded(rectFromTop(x: 230, y: 148, width: 22, height: 22), radius: 11, color: color(0x28c840))
drawText("Window Resizer", x: 282, y: 143, width: 420, height: 32, size: 20, weight: .bold, color: color(0xdbe1e8))

if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: rectFromTop(x: 178, y: 238, width: 96, height: 96))
} else {
    fillRounded(rectFromTop(x: 178, y: 238, width: 96, height: 96), radius: 20, color: .white)
}

drawText("Mac Window Resizer", x: 310, y: 240, width: 520, height: 42, size: 32, weight: .bold, color: color(0xf5f7fa))
drawText("Resize windows, build split layouts, and restore saved workspaces.", x: 310, y: 292, width: 720, height: 28, size: 20, weight: .medium, color: color(0xb8c0ca))

drawPanel(title: "Saved Layouts", symbol: "[]", x: 178, y: 370, width: 480, height: 246)
drawPill("Design Workspace", x: 222, y: 440, width: 270, fill: color(0x3a414a))
drawPill("Open & Arrange", x: 222, y: 514, width: 202, fill: color(0x0a84ff))
drawPill("Save Layout", x: 442, y: 514, width: 160, fill: color(0x203a54))
fillRounded(rectFromTop(x: 222, y: 578, width: 392, height: 34), radius: 8, color: color(0x31363d))
drawText("Three Columns   3 windows", x: 240, y: 584, width: 350, height: 20, size: 14, weight: .semibold, color: color(0xc7ced8))

drawPanel(title: "Layout Builder", symbol: "|||", x: 702, y: 370, width: 568, height: 346)
drawPill("Three Columns", x: 746, y: 440, width: 210, fill: color(0x3a414a))
drawText("Three equal windows across the screen.", x: 746, y: 505, width: 380, height: 24, size: 17, color: color(0xb8c0ca))

let rows = [("Left", "Browser - Window 1"), ("Center", "Editor - Window 1"), ("Right", "Notes - Window 1")]
for (index, row) in rows.enumerated() {
    let rowY = CGFloat(552 + (index * 58))
    drawText(row.0, x: 746, y: rowY + 8, width: 90, height: 22, size: 16, weight: .semibold, color: color(0xa9b2bd))
    fillRounded(rectFromTop(x: 858, y: rowY, width: 340, height: 38), radius: 10, color: color(0x515861))
    drawText(row.1, x: 878, y: rowY + 10, width: 300, height: 20, size: 16, weight: .semibold, color: color(0xf5f7fa))
}

drawPanel(title: "Size", symbol: "16:9", x: 178, y: 654, width: 480, height: 146)
drawPill("1920 x 1080", x: 222, y: 724, width: 174, fill: color(0x31363d))
drawText("Preset sizing for front or all windows.", x: 222, y: 782, width: 390, height: 22, size: 16, color: color(0xb8c0ca))

drawPill("Arrange Selected", x: 1012, y: 756, width: 230, fill: color(0x0a84ff))

drawPill("SwiftUI", x: 970, y: 246, width: 118, fill: color(0x31363d))
drawPill("macOS", x: 1106, y: 246, width: 116, fill: color(0x31363d))
drawPill("MIT", x: 1240, y: 246, width: 78, fill: color(0x31363d))

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not render README preview")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
print(outputURL.path)

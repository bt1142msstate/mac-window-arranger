import AppKit
import Foundation

let outputRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let iconsetURL = outputRoot.appendingPathComponent("WindowResizerIcon.iconset", isDirectory: true)
let fileManager = FileManager.default

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconSpec {
    let filename: String
    let pixels: Int
}

let specs = [
    IconSpec(filename: "icon_16x16.png", pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixels: 32),
    IconSpec(filename: "icon_32x32.png", pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixels: 64),
    IconSpec(filename: "icon_128x128.png", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixels: 256),
    IconSpec(filename: "icon_256x256.png", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixels: 512),
    IconSpec(filename: "icon_512x512.png", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixels: 1024)
]

func makeIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: pixels, height: pixels))

    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        return image
    }

    context.setShouldAntialias(true)
    NSGraphicsContext.current?.imageInterpolation = .high

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    context.saveGState()
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: size / 256, y: -size / 256)

    let strokeColor = NSColor(calibratedRed: 0x25 / 255, green: 0x2A / 255, blue: 0x31 / 255, alpha: 1).cgColor

    func setStrokeStyle() {
        context.setStrokeColor(strokeColor)
        context.setLineWidth(10)
        context.setLineCap(.round)
        context.setLineJoin(.round)
    }

    let backgroundPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: 256, height: 256),
        cornerWidth: 48,
        cornerHeight: 48,
        transform: nil
    )
    context.addPath(backgroundPath)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()

    let windowFrame = CGMutablePath()
    windowFrame.move(to: CGPoint(x: 158, y: 208))
    windowFrame.addLine(to: CGPoint(x: 72, y: 208))
    windowFrame.addCurve(
        to: CGPoint(x: 48, y: 184),
        control1: CGPoint(x: 58.75, y: 208),
        control2: CGPoint(x: 48, y: 197.25)
    )
    windowFrame.addLine(to: CGPoint(x: 48, y: 72))
    windowFrame.addCurve(
        to: CGPoint(x: 72, y: 48),
        control1: CGPoint(x: 48, y: 58.75),
        control2: CGPoint(x: 58.75, y: 48)
    )
    windowFrame.addLine(to: CGPoint(x: 184, y: 48))
    windowFrame.addCurve(
        to: CGPoint(x: 208, y: 72),
        control1: CGPoint(x: 197.25, y: 48),
        control2: CGPoint(x: 208, y: 58.75)
    )
    windowFrame.addLine(to: CGPoint(x: 208, y: 158))
    context.addPath(windowFrame)
    setStrokeStyle()
    context.strokePath()

    context.move(to: CGPoint(x: 48, y: 92))
    context.addLine(to: CGPoint(x: 208, y: 92))
    setStrokeStyle()
    context.strokePath()

    let dots: [(CGPoint, NSColor)] = [
        (CGPoint(x: 78, y: 72), NSColor(calibratedRed: 0xFF / 255, green: 0x5F / 255, blue: 0x57 / 255, alpha: 1)),
        (CGPoint(x: 104, y: 72), NSColor(calibratedRed: 0xFF / 255, green: 0xBD / 255, blue: 0x2E / 255, alpha: 1)),
        (CGPoint(x: 130, y: 72), NSColor(calibratedRed: 0x28 / 255, green: 0xC8 / 255, blue: 0x40 / 255, alpha: 1))
    ]

    for (center, color) in dots {
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
    }

    context.move(to: CGPoint(x: 158, y: 158))
    context.addLine(to: CGPoint(x: 208, y: 208))
    setStrokeStyle()
    context.strokePath()

    let outerArrowHead = CGMutablePath()
    outerArrowHead.move(to: CGPoint(x: 178, y: 208))
    outerArrowHead.addLine(to: CGPoint(x: 208, y: 208))
    outerArrowHead.addLine(to: CGPoint(x: 208, y: 178))
    context.addPath(outerArrowHead)
    setStrokeStyle()
    context.strokePath()

    let innerArrowHead = CGMutablePath()
    innerArrowHead.move(to: CGPoint(x: 184, y: 158))
    innerArrowHead.addLine(to: CGPoint(x: 158, y: 158))
    innerArrowHead.addLine(to: CGPoint(x: 158, y: 184))
    context.addPath(innerArrowHead)
    setStrokeStyle()
    context.strokePath()

    context.restoreGState()

    return image
}

for spec in specs {
    let image = makeIcon(pixels: spec.pixels)

    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        fatalError("Could not render \(spec.filename)")
    }

    try pngData.write(to: iconsetURL.appendingPathComponent(spec.filename), options: .atomic)
}

print(iconsetURL.path)

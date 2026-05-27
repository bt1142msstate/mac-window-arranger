import AppKit
import SwiftUI

struct AppIconView: View {
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 12
    var shadow = true

    var body: some View {
        Group {
            if let icon = NSImage(named: "WindowArrangerIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(shadow ? 0.14 : 0), radius: shadow ? 10 : 0, x: 0, y: shadow ? 5 : 0)
        .accessibilityHidden(true)
    }
}

struct ApplicationIconImage: View {
    let bundleIdentifier: String?
    let appName: String?
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if
            let bundleIdentifier,
            !bundleIdentifier.isEmpty,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if
            let appName,
            let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
            let bundleURL = runningApp.bundleURL
        {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

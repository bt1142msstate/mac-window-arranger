import AppKit
import SwiftUI

@main
struct WindowArrangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Window Arranger") {
                Button("Show Window Arranger") {
                    AppDelegate.shared?.bringMainWindowForward()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])

                Button("Mini Mode") {
                    AppDelegate.shared?.showCompactStatus(
                        message: "Ready to arrange windows.",
                        kind: .neutral
                    )
                }
                .keyboardShortcut("m", modifiers: [.command, .option])
            }

            WindowArrangerHelpCommands()
        }

        Window("Privacy Policy", id: "privacy-policy") {
            PrivacyPolicyView()
        }
        .windowResizability(.contentSize)
    }
}

struct WindowArrangerHelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Window Arranger Privacy Policy") {
                openWindow(id: "privacy-policy")
            }
        }
    }
}

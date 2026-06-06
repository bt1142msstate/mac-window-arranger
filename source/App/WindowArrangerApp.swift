import AppKit

@main
enum WindowArrangerApp {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = appDelegate
        app.mainMenu = makeMainMenu()
        app.run()
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "Window Arranger")
        appMenuItem.submenu = appMenu

        appMenu.addItem(
            menuItem(
                title: "Show Window Arranger",
                action: #selector(AppDelegate.showExpandedWindowFromMenu(_:)),
                keyEquivalent: "0",
                modifiers: [.command, .option]
            )
        )
        appMenu.addItem(
            menuItem(
                title: "Mini Mode",
                action: #selector(AppDelegate.showMiniModeFromMenu(_:)),
                keyEquivalent: "m",
                modifiers: [.command, .option]
            )
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            menuItem(
                title: "Quit Window Arranger",
                action: #selector(AppDelegate.quitFromMenu(_:)),
                keyEquivalent: "q",
                modifiers: [.command]
            )
        )

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)

        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu

        helpMenu.addItem(
            menuItem(
                title: "Check for Updates...",
                action: #selector(AppDelegate.checkForUpdatesFromMenu(_:)),
                keyEquivalent: "",
                modifiers: []
            )
        )
        helpMenu.addItem(
            menuItem(
                title: "Report an Issue...",
                action: #selector(AppDelegate.reportIssueFromMenu(_:)),
                keyEquivalent: "",
                modifiers: []
            )
        )
        helpMenu.addItem(.separator())
        helpMenu.addItem(
            menuItem(
                title: "Window Arranger Privacy Policy",
                action: #selector(AppDelegate.showPrivacyPolicyFromMenu(_:)),
                keyEquivalent: "",
                modifiers: []
            )
        )

        return mainMenu
    }

    private static func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = appDelegate
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

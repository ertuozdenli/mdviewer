import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If launched without a file (e.g. from Launchpad), offer an Open panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSDocumentController.shared.documents.isEmpty {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return true
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appName = "MD Viewer"

        func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                 _ mods: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
        }

        // App
        let appMenu = NSMenu()
        add(appMenu, "About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        appMenu.addItem(.separator())
        add(appMenu, "Hide \(appName)", #selector(NSApplication.hide(_:)), "h")
        add(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        add(appMenu, "Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")
        main.addItem(submenu(appMenu, appName))

        // File
        let file = NSMenu(title: "File")
        add(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        add(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Reload", #selector(MarkdownViewController.reloadFromDisk(_:)), "r")
        add(file, "Show in Finder", #selector(MarkdownViewController.showInFinder(_:)), "r", [.command, .shift])
        add(file, "Open in Default Editor", #selector(MarkdownViewController.openInEditor(_:)), "e")
        file.addItem(.separator())
        add(file, "Print…", #selector(NSDocument.printDocument(_:)), "p")
        main.addItem(submenu(file, "File"))

        // Edit
        let edit = NSMenu(title: "Edit")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        main.addItem(submenu(edit, "Edit"))

        // View
        let view = NSMenu(title: "View")
        add(view, "Actual Size", #selector(MarkdownViewController.actualSize(_:)), "0")
        add(view, "Zoom In", #selector(MarkdownViewController.zoomIn(_:)), "+")
        add(view, "Zoom In", #selector(MarkdownViewController.zoomIn(_:)), "=")
        view.items.last?.isAlternate = false
        view.items.last?.isHidden = true
        view.items.last?.allowsKeyEquivalentWhenHidden = true
        add(view, "Zoom Out", #selector(MarkdownViewController.zoomOut(_:)), "-")
        view.addItem(.separator())
        add(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        main.addItem(submenu(view, "View"))

        // Window
        let window = NSMenu(title: "Window")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        main.addItem(submenu(window, "Window"))
        NSApp.windowsMenu = window

        return main
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}

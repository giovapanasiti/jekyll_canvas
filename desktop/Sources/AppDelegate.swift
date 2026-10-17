import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var welcome: WelcomeWindowController!
    private var sites: [String: SiteWindowController] = [:]
    private let recentMenu = NSMenu(title: "Apri recenti")

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        // Route SIGTERM/SIGINT/SIGHUP through a normal quit so engines are always terminated.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { NSApp.terminate(nil) }
            src.resume()
            signalSources.append(src)
        }
        welcome = WelcomeWindowController()
        welcome.onOpenFolder = { [weak self] in self?.chooseFolder() }
        welcome.onOpenPath = { [weak self] path in self?.openSite(path) }

        NSApp.activate(ignoringOtherApps: true)

        // Automation: JEKYLL_CANVAS_OPEN=<path> or `--open <path>`.
        var autoOpen = ProcessInfo.processInfo.environment["JEKYLL_CANVAS_OPEN"]
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count { autoOpen = args[i + 1] }
        if let path = autoOpen, !path.isEmpty {
            openSite(path)
        } else {
            welcome.show()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if sites.isEmpty { welcome.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        sites.values.forEach { $0.shutdownEngineNow() }
    }

    // MARK: Opening sites

    @objc func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Apri"
        panel.message = "Scegli la cartella di un sito Jekyll"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            openSite(url.path)
        }
    }

    func openSite(_ rawPath: String) {
        let path = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath).standardizedFileURL.path
        guard SiteCheck.isJekyllSite(path) else {
            let a = NSAlert()
            a.messageText = "Questa cartella non sembra un sito Jekyll"
            a.informativeText = "Non ho trovato _config.yml, _config.yaml o _config.toml in:\n\(path)"
            a.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            if sites.isEmpty { welcome.show() }
            return
        }
        if let existing = sites[path] {
            existing.show()
            return
        }
        Recents.add(path)
        let controller = SiteWindowController(sitePath: path)
        controller.onClose = { [weak self] c in
            guard let self = self else { return }
            self.sites[c.sitePath] = nil
            if self.sites.isEmpty { self.welcome.show() }
        }
        sites[path] = controller
        welcome.window.orderOut(nil)
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    private var currentSite: SiteWindowController? {
        sites.values.first { $0.window.isKeyWindow } ?? (sites.count == 1 ? sites.values.first : nil)
    }

    // MARK: Menu actions

    @objc func openRecent(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openSite(path) }
    }

    @objc func clearRecents(_ sender: Any?) { Recents.clear() }

    @objc func showInFinder(_ sender: Any?) { currentSite?.revealInFinder() }

    @objc func reloadPage(_ sender: Any?) { currentSite?.reload() }

    @objc func showInspector(_ sender: Any?) { currentSite?.showInspector() }

    @objc func showWelcome(_ sender: Any?) { welcome.show() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        let paths = Recents.load()
        if paths.isEmpty {
            let item = NSMenuItem(title: "Nessun sito recente", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for p in paths {
                let item = NSMenuItem(title: (p as NSString).lastPathComponent,
                                      action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = p
                item.toolTip = p
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(title: "Svuota elenco", action: #selector(clearRecents(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
    }

    // MARK: Menu bar

    private func buildMenu() {
        let main = NSMenu()
        let appName = "Jekyll Canvas"

        func add(_ title: String, to menu: NSMenu, action: Selector?, key: String = "",
                 mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            menu.addItem(item)
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            item.submenu = m
            main.addItem(item)
            return m
        }

        let appMenu = submenu(appName)
        add("Informazioni su \(appName)", to: appMenu, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        appMenu.addItem(.separator())
        add("Nascondi \(appName)", to: appMenu, action: #selector(NSApplication.hide(_:)), key: "h")
        add("Nascondi altre", to: appMenu, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", mods: [.command, .option])
        add("Mostra tutte", to: appMenu, action: #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        add("Esci da \(appName)", to: appMenu, action: #selector(NSApplication.terminate(_:)), key: "q")

        let file = submenu("File")
        add("Apri cartella…", to: file, action: #selector(chooseFolder), key: "o", target: self)
        let recentItem = NSMenuItem(title: "Apri recenti", action: nil, keyEquivalent: "")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        file.addItem(recentItem)
        file.addItem(.separator())
        add("Mostra nel Finder", to: file, action: #selector(showInFinder(_:)), key: "r", mods: [.command, .shift], target: self)
        add("Mostra finestra iniziale", to: file, action: #selector(showWelcome(_:)), key: "0", target: self)
        file.addItem(.separator())
        add("Chiudi finestra", to: file, action: #selector(NSWindow.performClose(_:)), key: "w")

        // Standard selectors with nil target: the responder chain delivers them to the WKWebView.
        let edit = submenu("Modifica")
        add("Annulla", to: edit, action: Selector(("undo:")), key: "z")
        add("Ripeti", to: edit, action: Selector(("redo:")), key: "z", mods: [.command, .shift])
        edit.addItem(.separator())
        add("Taglia", to: edit, action: #selector(NSText.cut(_:)), key: "x")
        add("Copia", to: edit, action: #selector(NSText.copy(_:)), key: "c")
        add("Incolla", to: edit, action: #selector(NSText.paste(_:)), key: "v")
        add("Seleziona tutto", to: edit, action: #selector(NSText.selectAll(_:)), key: "a")

        let view = submenu("Vista")
        add("Ricarica", to: view, action: #selector(reloadPage(_:)), key: "r", target: self)
        add("Strumenti sviluppatore", to: view, action: #selector(showInspector(_:)), key: "i", mods: [.command, .option], target: self)

        let window = submenu("Finestra")
        add("Riduci a icona", to: window, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        add("Zoom", to: window, action: #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }
}

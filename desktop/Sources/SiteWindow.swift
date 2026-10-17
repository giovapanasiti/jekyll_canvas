import AppKit
import WebKit

final class SiteWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let sitePath: String
    let siteName: String
    let window: NSWindow
    var onClose: ((SiteWindowController) -> Void)?

    private let container = NSView()
    private var engine: EngineProcess?
    private var webView: WKWebView?
    private var loadingLog: NSTextView?
    private var spinner: NSProgressIndicator?
    private var closed = false

    init(sitePath: String) {
        self.sitePath = sitePath
        self.siteName = (sitePath as NSString).lastPathComponent
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()
        window.title = siteName
        window.minSize = NSSize(width: 1000, height: 640)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = container
        window.center()
        window.setFrameAutosaveName("site:" + sitePath)
        startEngine()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Engine

    func startEngine() {
        engine?.stop()
        showLoading()
        let e = EngineProcess(sitePath: sitePath)
        engine = e
        e.onLog = { [weak self] line in self?.appendLoadingLog(line) }
        e.onOutcome = { [weak self] outcome in self?.handle(outcome) }
        e.start()
    }

    private func handle(_ outcome: EngineProcess.Outcome) {
        switch outcome {
        case .ready(let url):
            showWebView(url)
        case .failed(let log):
            showError(log: log)
        case .died(let status):
            let log = (engine?.logLines ?? []).joined(separator: "\n")
            showError(log: log + "\n\nIl motore si è fermato (codice \(status)).")
        }
    }

    // MARK: Views

    private func setContent(_ view: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView = (view as? WKWebView)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func makeLogView() -> (NSScrollView, NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = .secondaryLabelColor
        tv.backgroundColor = .textBackgroundColor
        scroll.borderType = .lineBorder
        return (scroll, tv)
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        return l
    }

    private func showLoading() {
        let root = NSView()
        let title = label("Avvio di \(siteName)…", size: 18, weight: .semibold)
        let sp = NSProgressIndicator()
        sp.style = .spinning
        sp.controlSize = .small
        sp.startAnimation(nil)
        spinner = sp
        let (scroll, tv) = makeLogView()
        loadingLog = tv

        let header = NSStackView(views: [sp, title])
        header.spacing = 10
        let stack = NSStackView(views: [header, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setContent(root)
    }

    private func appendLoadingLog(_ line: String) {
        guard let tv = loadingLog else { return }
        tv.textStorage?.append(NSAttributedString(
            string: line + "\n",
            attributes: [.font: tv.font as Any, .foregroundColor: NSColor.secondaryLabelColor]))
        tv.scrollToEndOfDocument(nil)
    }

    private func showError(log: String) {
        let root = NSView()
        let title = label("Impossibile avviare il sito", size: 20, weight: .semibold)
        var views: [NSView] = [title]
        if log.contains("Bundler") || log.contains("Could not find") {
            views.append(label("Prova `bundle install` nella cartella del sito.", size: 13, color: .secondaryLabelColor))
        }
        let (scroll, tv) = makeLogView()
        tv.string = log
        tv.scrollToEndOfDocument(nil)
        views.append(scroll)

        let retry = NSButton(title: "Riprova", target: self, action: #selector(retry))
        retry.bezelStyle = .rounded
        retry.keyEquivalent = "\r"
        let term = NSButton(title: "Apri nel Terminale", target: self, action: #selector(openInTerminal))
        term.bezelStyle = .rounded
        let buttons = NSStackView(views: [retry, term])
        buttons.spacing = 10
        views.append(buttons)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        setContent(root)
    }

    @objc private func retry() { startEngine() }

    @objc private func openInTerminal() {
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: sitePath)],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration())
    }

    private func showWebView(_ url: URL) {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        if #available(macOS 13.3, *) { wv.isInspectable = true }
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = false
        setContent(wv)
        spinner = nil
        loadingLog = nil
        logErr("loading \(url.absoluteString)")
        wv.load(URLRequest(url: url))
    }

    // MARK: Menu actions (via AppDelegate)

    func reload() { webView?.reload() }

    func showInspector() {
        guard let wv = webView else { return }
        if let inspector = wv.value(forKey: "_inspector") as? NSObject {
            let sel = NSSelectorFromString("show")
            if inspector.responds(to: sel) { _ = inspector.perform(sel) }
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sitePath)])
    }

    /// Synchronous shutdown used at app quit.
    func shutdownEngineNow() {
        engine?.stopSynchronously()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }
        closed = true
        engine?.stop()
        engine = nil
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        window.delegate = nil
        onClose?(self)
    }

    // MARK: WKNavigationDelegate

    private func isLocal(_ url: URL) -> Bool {
        let host = url.host ?? ""
        return host == "127.0.0.1" || host == "localhost"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["about", "blob", "data", "javascript"].contains(scheme) || isLocal(url) {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logErr("webview didFinish \(webView.url?.absoluteString ?? "?")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logErr("webview didFail \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logErr("webview didFailProvisional \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        logErr("webview content process terminated; reloading")
        webView.reload()
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    private func alert(_ message: String, buttons: [String], accessory: NSView? = nil,
                       completion: @escaping (NSApplication.ModalResponse) -> Void) {
        let a = NSAlert()
        a.messageText = message
        buttons.forEach { a.addButton(withTitle: $0) }
        a.accessoryView = accessory
        a.beginSheetModal(for: window, completionHandler: completion)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        alert(message, buttons: ["OK"]) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        alert(message, buttons: ["OK", "Annulla"]) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert(prompt, buttons: ["OK", "Annulla"], accessory: field) {
            completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}

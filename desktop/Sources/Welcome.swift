import AppKit

final class WelcomeWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let table = NSTableView()
    private var paths: [String] = []
    private let emptyLabel = NSTextField(labelWithString: "Nessun sito recente")
    var onOpenFolder: (() -> Void)?
    var onOpenPath: ((String) -> Void)?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        super.init()
        window.title = "Jekyll Canvas"
        window.isReleasedWhenClosed = false
        build()
        window.center()
    }

    private func build() {
        let root = NSView()
        let title = NSTextField(labelWithString: "Jekyll Canvas")
        title.font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let subtitle = NSTextField(labelWithString: "Modifica un sito Jekyll direttamente dalla pagina.")
        subtitle.textColor = .secondaryLabelColor

        let open = NSButton(title: "Apri cartella…", target: self, action: #selector(openFolder))
        open.bezelStyle = .rounded
        open.controlSize = .large
        open.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        open.keyEquivalent = "\r"

        let recentTitle = NSTextField(labelWithString: "Siti recenti")
        recentTitle.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        recentTitle.textColor = .secondaryLabelColor

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("site"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 46
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.usesAlternatingRowBackgroundColors = false
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center

        let stack = NSStackView(views: [title, subtitle, open, recentTitle, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(24, after: open)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        window.contentView = root
        reload()
    }

    func reload() {
        paths = Recents.load()
        table.reloadData()
        emptyLabel.isHidden = !paths.isEmpty
    }

    func show() {
        reload()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openFolder() { onOpenFolder?() }

    @objc private func openSelected() {
        let row = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        guard row >= 0, row < paths.count else { return }
        onOpenPath?(paths[row])
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { paths.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let path = paths[row]
        let name = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let sub = NSTextField(labelWithString: (path as NSString).abbreviatingWithTildeInPath)
        sub.font = NSFont.systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingMiddle
        name.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [name, sub])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        let cell = NSTableCellView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

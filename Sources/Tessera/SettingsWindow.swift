import AppKit

/// A real settings window, independent of the transient menu bar popover.
final class SettingsWindowController: NSWindowController {
    init(model: AppModel, updater: Updater) {
        let navigation = SettingsNavigationController(model: model, updater: updater)
        let window = NSWindow(contentViewController: navigation)
        window.title = "Tessera Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "TesseraSettings")
        window.setContentSize(NSSize(width: 820, height: 600))
        window.minSize = NSSize(width: 760, height: 540)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsNavigationController: NSSplitViewController {
    let detail = NSTabViewController()
    private let sidebar = SettingsSidebarController()

    init(model: AppModel, updater: Updater) {
        super.init(nibName: nil, bundle: nil)
        detail.tabStyle = .unspecified
        detail.tabView.tabViewType = .noTabsNoBorder
        for (page, title) in [
            (AboutSettingsPage(updater: updater) as SettingsPage, "About"),
            (ShortcutSettingsPage(model: model), "Shortcuts"),
            (LayoutSettingsPage(model: model), "Layouts")
        ] {
            let item = NSTabViewItem(viewController: page)
            item.label = title
            detail.addTabViewItem(item)
        }
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 220
        sidebarItem.canCollapse = false
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: detail))
        sidebar.onSelect = { [weak self] index in self?.selectPage(at: index) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func selectPage(at index: Int) {
        guard detail.tabViewItems.indices.contains(index) else { return }
        detail.selectedTabViewItemIndex = index
        sidebar.select(index)
        view.window?.title = "Tessera Settings"
    }
}

private final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: (Int) -> Void = { _ in }
    private let table = NSTableView()
    private let items = [
        ("About", "info.circle"),
        ("Shortcuts", "keyboard"),
        ("Layouts", "rectangle.3.group")
    ]

    override func loadView() {
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        view = material

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("section"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowHeight = 38
        table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.allowsEmptySelection = false
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Settings sections")

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let title = SettingsPage.text("Tessera", size: 13, weight: .semibold, secondary: true)
        title.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(title)
        material.addSubview(scroll)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: material.safeAreaLayoutGuide.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: material.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: material.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: material.bottomAnchor, constant: -16)
        ])
        table.reloadData()
        select(0)
    }

    func select(_ index: Int) {
        guard table.selectedRow != index else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: items[row].1, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        let label = NSTextField(labelWithString: items[row].0)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        image.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(image)
        cell.addSubview(label)
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 20),
            image.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return }
        onSelect(table.selectedRow)
    }
}

/// Shared spacing and scrolling for the three native settings pages.
class SettingsPage: NSViewController {
    let stack = NSStackView()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = SettingsDocumentView()
        scroll.documentView = document
        view = scroll
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
    }

    func add(_ child: NSView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func addLeading(_ child: NSView) {
        let row = NSStackView(views: [child, NSView()])
        row.spacing = 0
        add(row)
    }

    static func styleButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    static func linkButton(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.font = .systemFont(ofSize: 13)
        button.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func heading(_ title: String, detail: String) {
        add(Self.text(title, size: 24, weight: .semibold))
        let description = Self.text(detail, secondary: true)
        add(description)
        stack.setCustomSpacing(6, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
    }

    static func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                     secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    static func row(_ title: String, control: NSView) -> NSStackView {
        let label = text(title)
        let row = NSStackView(views: [label, NSView(), control])
        row.alignment = .centerY
        row.spacing = 16
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        return row
    }

    static func group(_ rows: [NSView]) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0.5
        box.cornerRadius = 12
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.contentViewMargins = NSSize(width: 16, height: 6)
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                content.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            content.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        box.contentView = content
        return box
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

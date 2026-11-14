import AppKit
import Combine
import TesseraCore

final class LayoutSettingsPage: SettingsPage, NSTableViewDataSource, NSTableViewDelegate {
    private let model: AppModel
    private let table = NSTableView()
    private let up = NSButton(title: "Move up", target: nil, action: nil)
    private let down = NSButton(title: "Move down", target: nil, action: nil)
    private var subscriptions = Set<AnyCancellable>()
    private static let pasteboardType = NSPasteboard.PasteboardType("at.m-reschreiter.tessera.layout")

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading("Layouts", detail: "Drag layouts into the order you want, or select one and use Move up or Move down.")
        add(Self.text("The menu and layout shortcuts use this order. Changes save immediately.",
                      size: 12, secondary: true))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layout"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 62
        table.style = .inset
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Self.pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setAccessibilityLabel("Saved layouts in menu order")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.heightAnchor.constraint(equalToConstant: 280).isActive = true
        add(scroll)

        up.target = self
        up.action = #selector(moveLayoutUp)
        Self.styleButton(up)
        up.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)
        up.imagePosition = .imageLeading
        down.target = self
        down.action = #selector(moveLayoutDown)
        Self.styleButton(down)
        down.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        down.imagePosition = .imageLeading
        let buttons = NSStackView(views: [up, down, NSView()])
        buttons.spacing = 8
        add(buttons)

        model.$modes.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.table.reloadData()
            self?.updateButtons()
        }.store(in: &subscriptions)
        model.hotKeys.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.table.reloadData()
        }.store(in: &subscriptions)
        updateButtons()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { model.modes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard model.modes.indices.contains(row) else { return nil }
        let mode = model.modes[row]
        let position = Self.text("\(row + 1)", size: 12, weight: .medium, secondary: true)
        position.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let preview = LayoutThumbnail(mode: mode)
        preview.widthAnchor.constraint(equalToConstant: 62).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let name = Self.text(mode.name, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.maximumNumberOfLines = 1
        let shortcut = Self.text(model.hotKeys.label(forLayout: row) ?? "Not assigned", size: 12, secondary: true)
        shortcut.setContentHuggingPriority(.required, for: .horizontal)
        let rowView = NSStackView(views: [position, preview, name, NSView(), shortcut])
        rowView.spacing = 12
        rowView.alignment = .centerY
        rowView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard model.modes.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(model.modes[row].id.uuidString, forType: Self.pasteboardType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === table, operation == .above,
              sourceIndex(info) != nil else { return [] }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSource as? NSTableView === table, dropOperation == .above,
              let source = sourceIndex(info), (0...model.modes.count).contains(row) else { return false }
        let destination = row > source ? row - 1 : row
        move(from: source, to: destination)
        return true
    }

    private func sourceIndex(_ info: NSDraggingInfo) -> Int? {
        guard let value = info.draggingPasteboard.string(forType: Self.pasteboardType),
              let id = UUID(uuidString: value) else { return nil }
        return model.modes.firstIndex { $0.id == id }
    }

    private func move(from source: Int, to destination: Int) {
        guard model.modes.indices.contains(source), model.modes.indices.contains(destination) else { return }
        model.moveMode(from: source, to: destination)
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false)
        table.scrollRowToVisible(destination)
        updateButtons()
    }

    private func updateButtons() {
        let row = table.selectedRow
        up.isEnabled = row > 0
        down.isEnabled = row >= 0 && row < model.modes.count - 1
    }

    @objc private func moveLayoutUp() { move(from: table.selectedRow, to: table.selectedRow - 1) }
    @objc private func moveLayoutDown() { move(from: table.selectedRow, to: table.selectedRow + 1) }
}

private final class LayoutThumbnail: NSView {
    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for zone in mode.zones {
            let frame = NSRect(x: zone.minX * bounds.width + 1.5, y: zone.minY * bounds.height + 1.5,
                               width: max(0, zone.width * bounds.width - 3),
                               height: max(0, zone.height * bounds.height - 3))
            let shape = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            NSColor.controlAccentColor.withAlphaComponent(zone == mode.fillOrder.first ? 0.5 : 0.2).setFill()
            shape.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }
}

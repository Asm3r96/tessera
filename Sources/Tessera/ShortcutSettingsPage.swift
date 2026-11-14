import AppKit
import Combine
import TesseraCore

final class ShortcutSettingsPage: SettingsPage {
    private let model: AppModel
    private var layoutLabels: [NSTextField] = []
    private var subscriptions = Set<AnyCancellable>()
    private var recorders: [(HotKeys.Name, NSTextField)] = []

    init(model: AppModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading("Shortcuts", detail: "Click a shortcut, then press the keys you want to use. Changes save immediately.")
        add(Self.text("Press Escape to cancel. Click × or press Delete to clear a shortcut. Labels follow your keyboard layout.",
                      size: 12, secondary: true))

        let actions: [(String, HotKeys.Name)] = [
            ("Focus or restore window", HotKeys.focus),
            ("Next tab", HotKeys.nextTab),
            ("Previous tab", HotKeys.previousTab)
        ]
        add(Self.group(actions.map { title, name in
            Self.row(title, control: recorder(for: name, title: title))
        }))

        add(Self.text("Apply a layout", size: 15, weight: .semibold))
        add(Self.text("Shortcuts follow the positions in Layouts. Reorder your layouts to change what each position opens.",
                      size: 12, secondary: true))
        let rows = HotKeys.layouts.enumerated().map { index, name in
            let row = Self.row("", control: recorder(for: name, title: "Layout \(index + 1)"))
            layoutLabels.append(row.arrangedSubviews[0] as! NSTextField)
            return row
        }
        add(Self.group(rows))
        refreshLabels()
        model.$modes.sink { [weak self] modes in
            self?.refreshLabels(modes: modes)
        }.store(in: &subscriptions)
        model.hotKeys.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshRecorders()
        }.store(in: &subscriptions)
        let reset = NSButton(title: "Restore default shortcuts…", target: self, action: #selector(restoreDefaults))
        Self.styleButton(reset)
        addLeading(reset)
    }

    private func recorder(for name: HotKeys.Name, title: String) -> NSView {
        let field = model.hotKeys.recorder(for: name, title: title)
        recorders.append((name, field))
        return field
    }

    private func refreshRecorders() {
        for (name, field) in recorders { field.stringValue = name.shortcut?.description ?? "" }
    }

    private func refreshLabels(modes: [Mode]? = nil) {
        let modes = modes ?? model.modes
        for (index, label) in layoutLabels.enumerated() {
            label.stringValue = modes.indices.contains(index)
                ? "\(index + 1). \(modes[index].name)"
                : "\(index + 1). No saved layout"
        }
    }

    @objc private func restoreDefaults() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Restore default shortcuts?"
        alert.informativeText = "This replaces all your shortcut assignments with Tessera's defaults."
        alert.addButton(withTitle: "Restore defaults")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            self.model.hotKeys.restoreDefaults()
        }
    }
}

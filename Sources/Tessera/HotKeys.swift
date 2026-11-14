import AppKit
import Carbon
import KeyboardShortcuts

/// One shortcut store for registration, recording, and keyboard-layout-aware labels.
final class HotKeys: ObservableObject {
    typealias Name = KeyboardShortcuts.Name
    typealias Shortcut = KeyboardShortcuts.Shortcut

    static let layouts: [Name] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ].enumerated().map { index, key in
        Name("layout\(index + 1)", default: Shortcut(carbonKeyCode: key, carbonModifiers: controlKey | optionKey))
    }
    static let focus = Name("focus", default: Shortcut(.z, modifiers: [.control, .option]))
    static let nextTab = Name("nextTab", default: Shortcut(.backtick, modifiers: [.control, .option]))
    static let previousTab = Name("previousTab", default: Shortcut(.backtick, modifiers: [.control, .option, .shift]))
    static var names: [Name] { [focus, nextTab, previousTab] + layouts }

    var onPress: ((Int) -> Void)?
    var onTab: ((Int) -> Void)?
    var onFocus: (() -> Void)?
    @Published private(set) var revision = 0

    private var registered = false
    private var accepted: [Name: Shortcut] = [:]
    private var inputObserver: NSObjectProtocol?

    init() {
        rememberShortcuts()
        inputObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLabels() }
    }

    deinit {
        if let inputObserver { DistributedNotificationCenter.default().removeObserver(inputObserver) }
    }

    func register() {
        guard !registered else { return }
        registered = true
        for (index, name) in Self.layouts.enumerated() {
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in self?.onPress?(index) }
        }
        KeyboardShortcuts.onKeyDown(for: Self.focus) { [weak self] in self?.onFocus?() }
        KeyboardShortcuts.onKeyDown(for: Self.nextTab) { [weak self] in self?.onTab?(1) }
        KeyboardShortcuts.onKeyDown(for: Self.previousTab) { [weak self] in self?.onTab?(-1) }
    }

    @MainActor
    func label(forLayout index: Int) -> String? {
        guard Self.layouts.indices.contains(index) else { return nil }
        return KeyboardShortcuts.getShortcut(for: Self.layouts[index])?.description
    }

    func refreshLabels() { revision += 1 }

    func recorder(for name: Name, title: String) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name) { [weak self] shortcut in
            guard let self else { return }
            if !self.acceptRecordedShortcut(shortcut, for: name) {
                // Finish the recorder's event handler before presenting a sheet.
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Shortcut already in use"
                    alert.informativeText = "Another Tessera action uses this shortcut. Choose a different combination."
                    if let window = NSApp.keyWindow { alert.beginSheetModal(for: window) }
                }
                return
            }
        }
        recorder.setAccessibilityLabel("Shortcut for \(title)")
        recorder.toolTip = "Click, then press the keys to use. Press Escape to cancel, or Delete to clear."
        return recorder
    }

    /// The recorder stores its proposed value first. Reject app-local conflicts without losing the previous value.
    @discardableResult
    func acceptRecordedShortcut(_ shortcut: Shortcut?, for name: Name) -> Bool {
        if let shortcut, Self.names.contains(where: { $0 != name && KeyboardShortcuts.getShortcut(for: $0) == shortcut }) {
            KeyboardShortcuts.setShortcut(accepted[name], for: name)
            return false
        }
        accepted[name] = shortcut
        refreshLabels()
        return true
    }

    func restoreDefaults() {
        // Clear first so swapping two assignments cannot leave duplicate registrations.
        for name in Self.names { KeyboardShortcuts.setShortcut(nil, for: name) }
        KeyboardShortcuts.reset(Self.names)
        rememberShortcuts()
        refreshLabels()
    }

    private func rememberShortcuts() {
        accepted = Dictionary(uniqueKeysWithValues: Self.names.compactMap { name in
            KeyboardShortcuts.getShortcut(for: name).map { (name, $0) }
        })
    }
}

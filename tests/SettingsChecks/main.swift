import AppKit
import KeyboardShortcuts
import TesseraCore

// A separate app bundle isolates these checks from Tessera's saved settings.
let domain = "at.m-reschreiter.tessera.settings-checks"
guard Bundle.main.bundleIdentifier == domain else { fatalError("Settings checks need their isolated app bundle") }
UserDefaults.standard.removePersistentDomain(forName: domain)
defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)

var checks = 0
func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    checks += 1
}
func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { descendants($0, of: type) }
}

try MainActor.assumeIsolated {
    let model = AppModel.shared
    let keys = model.hotKeys
    check(HotKeys.names.count == 12, "All existing actions can be customized")
    let defaults = HotKeys.names.compactMap { KeyboardShortcuts.getShortcut(for: $0) }
    check(defaults.count == 12 && Set(defaults).count == 12, "Default shortcuts exist and do not collide")
    check(keys.label(forLayout: 0)?.isEmpty == false, "Layout label shows the current shortcut")
    check(keys.label(forLayout: 9) == nil, "Layouts beyond the nine positions have no shortcut")

    let custom = KeyboardShortcuts.Shortcut(.k, modifiers: [.control, .command])
    KeyboardShortcuts.setShortcut(custom, for: HotKeys.focus)
    check(keys.acceptRecordedShortcut(custom, for: HotKeys.focus), "A unique shortcut is accepted")
    check(KeyboardShortcuts.Name("focus").shortcut == custom, "The assignment is saved")
    let duplicate = KeyboardShortcuts.getShortcut(for: HotKeys.nextTab)!
    KeyboardShortcuts.setShortcut(duplicate, for: HotKeys.focus)
    check(!keys.acceptRecordedShortcut(duplicate, for: HotKeys.focus), "Duplicate assignments are rejected")
    check(KeyboardShortcuts.getShortcut(for: HotKeys.focus) == custom, "A rejected assignment restores the previous keys")
    KeyboardShortcuts.setShortcut(nil, for: HotKeys.focus)
    check(keys.acceptRecordedShortcut(nil, for: HotKeys.focus), "A shortcut can be cleared")
    check(KeyboardShortcuts.getShortcut(for: HotKeys.focus) == nil, "Clearing disables the action")
    keys.restoreDefaults()
    check(HotKeys.names.compactMap { $0.shortcut } == defaults, "Restore defaults restores every action")

    let originalIDs = model.modes.map(\.id)
    check(originalIDs.count > 1, "Default layouts can be reordered")
    model.moveMode(from: 0, to: model.modes.count - 1)
    check(model.modes.last?.id == originalIDs.first, "Moving a layout changes the model order")
    let stored = UserDefaults.standard.data(forKey: "modes")!
    let saved = try JSONDecoder().decode([Mode].self, from: stored)
    check(saved.map(\.id) == model.modes.map(\.id), "Reordering is saved immediately")

    let controller = SettingsWindowController(model: model, updater: .shared)
    let window = controller.window!
    check(window.styleMask.contains(.closable), "Settings has a standard close button")
    let navigation = window.contentViewController as! SettingsNavigationController
    let tabs = navigation.detail
    check(tabs.tabViewItems.map(\.label) == ["About", "Shortcuts", "Layouts"], "Settings has the requested sections")
    check(tabs.tabView.tabViewType == .noTabsNoBorder, "Old toolbar tabs are removed")
    check(navigation.splitViewItems.count == 2, "Settings has a sidebar and a detail pane")
    let sidebar = descendants(navigation.splitViewItems[0].viewController.view, of: NSTableView.self)[0]
    check(sidebar.style == .sourceList && sidebar.numberOfRows == 3, "Sidebar uses a native source list")
    sidebar.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    check(tabs.selectedTabViewItemIndex == 1, "Clicking a sidebar row changes the page")

    for (index, item) in tabs.tabViewItems.enumerated() {
        navigation.selectPage(at: index)
        let page = item.viewController as! SettingsPage
        _ = page.view
        window.contentView?.layoutSubtreeIfNeeded()
        page.view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        check(!page.stack.arrangedSubviews.isEmpty, "\(item.label) builds its content")
        check(page.stack.frame.width > 400, "\(item.label) fits the settings window")
        check(sidebar.selectedRow == index, "Sidebar selection follows the active page")
        if let directory = ProcessInfo.processInfo.environment["TESSERA_SETTINGS_PREVIEWS"],
           let bitmap = page.stack.bitmapImageRepForCachingDisplay(in: page.stack.bounds) {
            page.stack.cacheDisplay(in: page.stack.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(item.label.lowercased()).png"))
            }
        }
    }
    let aboutPage = tabs.tabViewItems[0].viewController!
    let switches = descendants(aboutPage.view, of: NSSwitch.self)
    check(switches.count == 1, "Automatic updates uses a switch")
    check(switches[0].state == .off && !switches[0].isEnabled, "Source builds show automatic updates as off")
    let aboutButtons = descendants(aboutPage.view, of: NSButton.self)
    check(aboutButtons.contains { $0.title == "View releases" && $0.isEnabled }, "Source builds offer an active releases button")
    check(aboutButtons.allSatisfy { $0.frame.width < 250 }, "About buttons do not stretch across the page")
    let shortcutPage = tabs.tabViewItems[1].viewController!
    let recorders = descendants(shortcutPage.view, of: KeyboardShortcuts.RecorderCocoa.self)
    check(recorders.count == 12, "Every action has a recorder")
    check(recorders.allSatisfy { $0.frame.width >= 100 && $0.frame.height >= 20 }, "Recorders have usable dimensions")
    let layoutPage = tabs.tabViewItems[2].viewController!
    let tables = descendants(layoutPage.view, of: NSTableView.self)
    check(tables.count == 1 && tables[0].numberOfRows == model.modes.count, "All saved layouts appear in the order list")
    window.close()
    print("All \(checks) settings checks passed.")
}

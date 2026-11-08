import AppKit
import TesseraCore
import ApplicationServices
import ServiceManagement

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var modes: [Mode] { didSet { saveModes() } }
    @Published var gap: Double { didSet { UserDefaults.standard.set(gap, forKey: Keys.gap) } }
    @Published var editing: Mode?
    /// The mode card under the pointer. Its preview shows on screen.
    @Published var hovered: UUID? { didSet { if hovered != oldValue { updatePreview() } } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Tessera: launch at login failed: \(error)")
            }
        }
    }
    @Published private(set) var hasAccess = AXIsProcessTrusted()

    private let hotKeys = HotKeys()
    private let drag = DragWatcher()
    private let overlay = ZoneOverlay()
    private let tabBars = TabBars()
    private var activationObserver: NSObjectProtocol?
    private var sessions: [CGDirectDisplayID: TileSession] = [:]
    private var dragItems: [CGDirectDisplayID: [ZoneItem]] = [:]
    private var dragTarget: String?

    private enum Keys {
        static let modes = "modes"
        static let gap = "gap"
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.modes),
           let saved = try? JSONDecoder().decode([Mode].self, from: data) {
            modes = saved
        } else {
            modes = Mode.defaults
        }
        gap = UserDefaults.standard.object(forKey: Keys.gap) as? Double ?? 8
    }

    func start() {
        hotKeys.onPress = { [weak self] index in self?.apply(at: index) }
        hotKeys.onTab = { [weak self] offset in self?.cycleTab(by: offset) }
        hotKeys.register()
        drag.onStart = { [weak self] window in self?.beginDrag(window) ?? false }
        drag.onMove = { [weak self] window, point, mode in self?.moveDrag(window, point, mode: mode) }
        drag.onDrop = { [weak self] window, point, mode in self?.drop(window, point, mode: mode) }
        drag.start()
        tabBars.actions = TabActions(
            show: { [weak self] window in self?.session(of: window)?.show(window) },
            close: { WindowArranger.close($0) },
            dragMoved: { [weak self] window, point in self?.moveDrag(window, point, mode: .place, fromBar: true) },
            dragEnded: { [weak self] window, point in self?.dropFromBar(window, point) })
        // Command-Tab and the Dock switch apps. The app's focused window becomes the shown tab.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let window = WindowArranger.focusedWindow(of: app.processIdentifier) else { return }
            self.session(of: window)?.noteFocus(window)
        }
        if !AXIsProcessTrusted() { requestAccess() }
    }

    func refresh() {
        hasAccess = AXIsProcessTrusted()
        let enabled = SMAppService.mainApp.status == .enabled
        if launchAtLogin != enabled { launchAtLogin = enabled }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccess = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func apply(at index: Int) {
        guard modes.indices.contains(index) else { return }
        apply(modes[index])
    }

    func apply(_ mode: Mode) {
        guard AXIsProcessTrusted() else { requestAccess(); return }
        hasAccess = true
        hovered = nil
        guard let screen = Screens.underMouse() else { return }
        let placement = WindowArranger.plan(mode, on: screen, gap: gap, keep: sessions[screen.displayID]?.windows ?? [])
        sessions[placement.screenID] = nil
        for window in placement.stacks.joined() {
            for session in sessions.values { session.remove(window) }
        }
        WindowArranger.apply(placement)
        // The first tab of each zone shows on top. The front zone comes last, so its window stays active.
        if placement.stacks.contains(where: { $0.count > 1 }) {
            for stack in placement.stacks.reversed() { if let window = stack.first { WindowArranger.focus(window) } }
        }
        let session = TileSession(placement, gap: gap)
        session.onChange = { [weak self] in self?.updateTabBars() }
        sessions[placement.screenID] = session
        updateTabBars()
    }

    // MARK: Tabs

    private func session(of window: AXUIElement) -> TileSession? {
        sessions.values.first { $0.index(of: window) != nil }
    }

    /// Shows the next or previous tab in the zone of the focused window, or else the zone under the pointer.
    private func cycleTab(by offset: Int) {
        if let app = NSWorkspace.shared.frontmostApplication,
           let window = WindowArranger.focusedWindow(of: app.processIdentifier),
           let session = session(of: window), let index = session.index(of: window),
           session.slots[index].tabs.items.count > 1 {
            session.cycle(index, by: offset)
            return
        }
        let point = Screens.mouse
        guard let session = sessions.values.first(where: { $0.area.contains(point) }),
              let index = session.zone(at: point) else { return }
        session.cycle(index, by: offset)
    }

    private func updateTabBars() {
        var groups: [TabGroup] = []
        for (id, session) in sessions {
            for (index, slot) in session.slots.enumerated() where slot.tabs.items.count > 1 {
                let chips = slot.tabs.items.enumerated().map { number, window in
                    let app = WindowArranger.pid(of: window).flatMap { NSRunningApplication(processIdentifier: $0) }
                    return TabChip(id: number, window: window, icon: app?.icon, name: app?.localizedName ?? "Window",
                                   title: "", shown: window == slot.window)
                }
                groups.append(TabGroup(key: "\(id)-\(index)", zone: slot.frame, chips: chips))
            }
        }
        tabBars.update(groups)
    }

    // MARK: Preview

    private func updatePreview() {
        guard let id = hovered, let mode = modes.first(where: { $0.id == id }),
              AXIsProcessTrusted(), let screen = Screens.underMouse() else {
            overlay.hideAll()
            return
        }
        let placement = WindowArranger.plan(mode, on: screen, gap: gap, keep: sessions[screen.displayID]?.windows ?? [])
        let items = placement.frames.indices.map { index in
            var item = zoneItem(index, placement.frames[index], placement.stacks[index].first, empty: "Stays empty")
            if placement.stacks[index].count > 1 { item.detail = "+\(placement.stacks[index].count - 1) as tabs" }
            return item
        }
        overlay.hideAll()
        overlay.show(screenID: placement.screenID, area: placement.area, items: items)
    }

    // MARK: Drag and drop

    private func beginDrag(_ window: AXUIElement) -> Bool {
        guard !sessions.isEmpty else { return false }
        dragItems = sessions.mapValues { session in
            session.slots.enumerated().map { zoneItem($0, $1.frame, $1.window, empty: "Drop a window here") }
        }
        dragTarget = nil
        return true
    }

    private func moveDrag(_ window: AXUIElement, _ point: CGPoint, mode: DropMode, fromBar: Bool = false) {
        if fromBar, dragItems.isEmpty { _ = beginDrag(window) }
        let free = mode == .free
        let target = free ? nil : sessions.first { $0.value.area.contains(point) }
        let index = target?.value.zone(at: point)
        let key = free ? "free" : "\(target?.key ?? 0)-\(index ?? -1)-\(mode)"
        guard key != dragTarget else { return }
        dragTarget = key
        guard !free else {
            overlay.hideAll()
            return
        }
        for (id, session) in sessions {
            var items = dragItems[id] ?? []
            if id == target?.key, let index, items.indices.contains(index) {
                items[index].highlighted = true
                items[index].detail = fromBar ? barAction(for: window, in: session, at: index)
                                              : action(for: window, in: session, at: index, mode: mode)
            }
            overlay.show(screenID: id, area: session.area, items: items)
        }
    }

    /// Drop on a zone to place the window. Hold Command to add it as a tab.
    /// Drop with Option held, or off the tiled screens, to free it.
    private func drop(_ window: AXUIElement, _ point: CGPoint, mode: DropMode) {
        endDrag()
        let target = mode == .free ? nil : sessions.first { $0.value.area.contains(point) }
        for (id, session) in sessions where id != target?.key { session.remove(window) }
        guard let session = target?.value, let index = session.zone(at: point) else {
            target?.value.remove(window)
            return
        }
        // Let the system finish the drag before Tessera moves the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if mode == .tab { session.addTab(window, at: index) } else { session.place(window, at: index) }
        }
    }

    /// A tab dragged out of its bar moves to the zone under the pointer, on top. Elsewhere it stays.
    private func dropFromBar(_ window: AXUIElement, _ point: CGPoint) {
        endDrag()
        guard let target = sessions.first(where: { $0.value.area.contains(point) })?.value,
              let index = target.zone(at: point) else { return }
        if let source = session(of: window), source !== target { source.remove(window) }
        target.addTab(window, at: index)
        WindowArranger.focus(window)
    }

    private func endDrag() {
        overlay.hideAll()
        dragItems = [:]
        dragTarget = nil
    }

    private func action(for window: AXUIElement, in session: TileSession, at index: Int, mode: DropMode) -> String {
        let tabs = session.slots[index].tabs
        if mode == .tab {
            if tabs.contains(window) { return "Already a tab here" }
            return tabs.shown == nil ? "Move here" : "Add as tab"
        }
        guard let occupant = tabs.shown else { return "Move here" }
        if occupant == window || tabs.contains(window) { return "Keep here" }
        let name = appName(occupant)
        return session.index(of: window) == nil ? "Replace \(name) · ⌘ adds a tab" : "Swap with \(name) · ⌘ adds a tab"
    }

    private func barAction(for window: AXUIElement, in session: TileSession, at index: Int) -> String {
        session.slots[index].tabs.contains(window) ? "Keep here" : "Move here as tab"
    }

    private func zoneItem(_ index: Int, _ frame: CGRect, _ window: AXUIElement?, empty: String) -> ZoneItem {
        guard let window, let pid = WindowArranger.pid(of: window) else {
            return ZoneItem(id: index, frame: frame, icon: nil, title: "Empty", detail: empty)
        }
        let app = NSRunningApplication(processIdentifier: pid)
        return ZoneItem(id: index, frame: frame, icon: app?.icon, title: app?.localizedName ?? "Window",
                        detail: WindowArranger.title(of: window))
    }

    private func appName(_ window: AXUIElement) -> String {
        WindowArranger.pid(of: window).flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName } ?? "window"
    }

    func save(_ mode: Mode) {
        if let index = modes.firstIndex(where: { $0.id == mode.id }) {
            modes[index] = mode
        } else {
            modes.append(mode)
        }
    }

    func delete(_ mode: Mode) {
        modes.removeAll { $0.id == mode.id }
    }

    private func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: Keys.modes)
        }
    }
}

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
        hotKeys.register()
        drag.onStart = { [weak self] window in self?.beginDrag(window) ?? false }
        drag.onMove = { [weak self] window, point, free in self?.moveDrag(window, point, free: free) }
        drag.onDrop = { [weak self] window, point, free in self?.drop(window, point, free: free) }
        drag.start()
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
        for window in placement.windows.compactMap({ $0 }) {
            for session in sessions.values { session.remove(window) }
        }
        WindowArranger.apply(placement)
        sessions[placement.screenID] = TileSession(placement, gap: gap)
    }

    // MARK: Preview

    private func updatePreview() {
        guard let id = hovered, let mode = modes.first(where: { $0.id == id }),
              AXIsProcessTrusted(), let screen = Screens.underMouse() else {
            overlay.hideAll()
            return
        }
        let placement = WindowArranger.plan(mode, on: screen, gap: gap, keep: sessions[screen.displayID]?.windows ?? [])
        let items = placement.frames.indices.map {
            zoneItem($0, placement.frames[$0], placement.windows[$0], empty: "Stays empty")
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

    private func moveDrag(_ window: AXUIElement, _ point: CGPoint, free: Bool) {
        let target = free ? nil : sessions.first { $0.value.area.contains(point) }
        let index = target?.value.zone(at: point)
        let key = free ? "free" : "\(target?.key ?? 0)-\(index ?? -1)"
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
                items[index].detail = action(for: window, in: session, at: index)
            }
            overlay.show(screenID: id, area: session.area, items: items)
        }
    }

    /// Drop on a zone to place the window. Drop with Option held, or off the tiled screens, to free it.
    private func drop(_ window: AXUIElement, _ point: CGPoint, free: Bool) {
        overlay.hideAll()
        dragItems = [:]
        dragTarget = nil
        let target = free ? nil : sessions.first { $0.value.area.contains(point) }
        for (id, session) in sessions where id != target?.key { session.remove(window) }
        guard let session = target?.value, let index = session.zone(at: point) else {
            target?.value.remove(window)
            return
        }
        // Let the system finish the drag before Tessera moves the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { session.place(window, at: index) }
    }

    private func action(for window: AXUIElement, in session: TileSession, at index: Int) -> String {
        guard let occupant = session.slots[index].window else { return "Move here" }
        if CFEqual(occupant, window) { return "Keep here" }
        let name = appName(occupant)
        return session.index(of: window) == nil ? "Replace \(name)" : "Swap with \(name)"
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

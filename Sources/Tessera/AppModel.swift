import AppKit
import ApplicationServices
import ServiceManagement

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var modes: [Mode] { didSet { saveModes() } }
    @Published var gap: Double { didSet { UserDefaults.standard.set(gap, forKey: Keys.gap) } }
    @Published var editing: Mode?
    @Published var hovered: UUID?
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
    private var session: TileSession?

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
        session = nil
        session = TileSession(windows: WindowArranger.arrange(mode, gap: gap), gap: gap)
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

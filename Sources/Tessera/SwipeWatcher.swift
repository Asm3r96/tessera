import AppKit
import TesseraCore

/// Watches the discrete swipe gesture that macOS assigns to page navigation.
final class SwipeWatcher {
    var onSwipe: (Int, CGPoint) -> Bool = { _, _ in false }

    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            _ = self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
        if globalMonitor == nil {
            NSLog("Tessera: could not monitor swipe gestures")
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let offset = TabSwipe.offset(x: Double(event.deltaX), y: Double(event.deltaY)) else { return false }
        return onSwipe(offset, Screens.mouse)
    }
}

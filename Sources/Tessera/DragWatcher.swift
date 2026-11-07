import AppKit
import ApplicationServices

/// Detects when you drag a window by its title bar, and where you drop it.
final class DragWatcher {
    /// Called once when a window starts to move. Return false to ignore this drag.
    var onStart: (AXUIElement) -> Bool = { _ in false }
    /// Called while the window moves. `free` is true while Option is held.
    var onMove: (AXUIElement, CGPoint, Bool) -> Void = { _, _, _ in }
    var onDrop: (AXUIElement, CGPoint, Bool) -> Void = { _, _, _ in }

    private var monitor: Any?
    private var window: AXUIElement?
    private var startFrame: CGRect?
    private var dragging = false

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handle(event)
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent) {
        let point = Screens.mouse
        let free = event.modifierFlags.contains(.option)
        switch event.type {
        case .leftMouseDown:
            dragging = false
            window = WindowArranger.window(at: point)
            startFrame = window.flatMap(WindowArranger.frame(of:))
        case .leftMouseDragged:
            guard let window else { return }
            if dragging {
                onMove(window, point, free)
                return
            }
            guard let start = startFrame, let frame = WindowArranger.frame(of: window) else { return }
            if abs(frame.width - start.width) > 1 || abs(frame.height - start.height) > 1 {
                // A resize, not a move.
                self.window = nil
                return
            }
            guard hypot(frame.minX - start.minX, frame.minY - start.minY) > 4 else { return }
            if onStart(window) {
                dragging = true
                onMove(window, point, free)
            } else {
                self.window = nil
            }
        case .leftMouseUp:
            if dragging, let window { onDrop(window, point, free) }
            dragging = false
            window = nil
        default:
            break
        }
    }
}

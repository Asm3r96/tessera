import AppKit
import ApplicationServices

/// What a drop does, chosen by the keys held at the drop.
enum DropMode {
    /// No key: swap, replace or move.
    case place
    /// Command: add the window as a tab.
    case tab
    /// Option: free the window from the layout.
    case free

    init(_ flags: NSEvent.ModifierFlags) {
        if flags.contains(.option) {
            self = .free
        } else if flags.contains(.command) {
            self = .tab
        } else {
            self = .place
        }
    }
}

/// Detects when you drag a window by its title bar, and where you drop it.
final class DragWatcher {
    /// Called once when a window starts to move. Return false to ignore this drag.
    var onStart: (AXUIElement) -> Bool = { _ in false }
    /// Called while the window moves.
    var onMove: (AXUIElement, CGPoint, DropMode) -> Void = { _, _, _ in }
    var onDrop: (AXUIElement, CGPoint, DropMode) -> Void = { _, _, _ in }

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
        let mode = DropMode(event.modifierFlags)
        switch event.type {
        case .leftMouseDown:
            dragging = false
            window = WindowArranger.window(at: point)
            startFrame = window.flatMap(WindowArranger.frame(of:))
        case .leftMouseDragged:
            guard let window else { return }
            if dragging {
                onMove(window, point, mode)
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
                onMove(window, point, mode)
            } else {
                self.window = nil
            }
        case .leftMouseUp:
            if dragging, let window { onDrop(window, point, mode) }
            dragging = false
            window = nil
        default:
            break
        }
    }
}

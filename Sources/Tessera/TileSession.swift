import AppKit
import TesseraCore
import ApplicationServices

/// The applied mode on one screen: zone frames and the tabs in each zone.
/// Resizing a window moves its zone edges, and the neighbor zones follow.
final class TileSession {
    struct Slot {
        var frame: CGRect
        var tabs: TabStack<AXUIElement>
        var quietUntil: Date
        /// The tab that shows.
        var window: AXUIElement? { tabs.shown }
    }

    let screenID: CGDirectDisplayID
    let area: CGRect
    private(set) var slots: [Slot]
    /// Called after tabs, the shown tab, or a zone frame change.
    var onChange: () -> Void = {}
    private let gap: Double
    private var observers: [pid_t: AXObserver] = [:]
    private static let notifications = [kAXResizedNotification, kAXMovedNotification,
                                        kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification]

    init(_ placement: Placement, gap: Double) {
        screenID = placement.screenID
        area = placement.area
        self.gap = gap
        let quiet = Date().addingTimeInterval(0.5)
        slots = zip(placement.frames, placement.stacks).map { Slot(frame: $0, tabs: TabStack($1), quietUntil: quiet) }
        for window in placement.stacks.joined() { observe(window) }
    }

    deinit {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    /// Shown windows in zone order, then the waiting tabs.
    var windows: [AXUIElement] {
        let shown = slots.compactMap(\.window)
        let waiting = slots.flatMap { slot in slot.tabs.items.filter { $0 != slot.window } }
        return shown + waiting
    }

    func index(of window: AXUIElement) -> Int? {
        slots.firstIndex { $0.tabs.contains(window) }
    }

    /// The zone under a point, or the nearest zone when the point is in a gap.
    func zone(at point: CGPoint) -> Int? {
        guard area.contains(point) else { return nil }
        return slots.indices.min { distance(point, slots[$0].frame) < distance(point, slots[$1].frame) }
    }

    /// The zone whose drop target, the box in its center, contains the point.
    func target(at point: CGPoint) -> Int? {
        slots.indices.first { DropTarget.rect(in: slots[$0].frame).contains(point) }
    }

    /// Puts a window into a zone. A window from another zone swaps places with the shown tab there.
    /// A new window replaces the shown tab, which stays where it is, behind.
    func place(_ window: AXUIElement, at index: Int) {
        let from = self.index(of: window)
        guard from != index else {
            slots[index].tabs.show(window)
            snap(index)
            onChange()
            return
        }
        let occupant = slots[index].window
        if let from {
            if let occupant {
                slots[from].tabs.replace(window, with: occupant)
            } else {
                slots[from].tabs.remove(window)
                revealFront(from)
            }
            snap(from)
        } else {
            if let occupant { unobserve(occupant) }
            observe(window)
        }
        if let occupant { slots[index].tabs.replace(occupant, with: window) } else { slots[index].tabs.add(window) }
        snap(index)
        onChange()
    }

    /// Adds a window as a tab in a zone. It shows on top; the tab that was there waits behind it.
    func addTab(_ window: AXUIElement, at index: Int) {
        if let from = self.index(of: window), from != index {
            slots[from].tabs.remove(window)
            revealFront(from)
        } else if self.index(of: window) == nil {
            observe(window)
        }
        slots[index].tabs.add(window)
        snap(index)
        onChange()
    }

    func remove(_ window: AXUIElement) {
        guard let index = index(of: window) else { return }
        unobserve(window)
        let wasShown = slots[index].window == window
        slots[index].tabs.remove(window)
        if wasShown { revealFront(index) }
        onChange()
    }

    /// Shows a tab and brings it to the front.
    func show(_ window: AXUIElement) {
        guard let index = index(of: window) else { return }
        slots[index].tabs.show(window)
        snap(index)
        WindowArranger.focus(window)
        onChange()
    }

    /// Shows the next tab (offset 1) or the previous tab (offset -1) in a zone.
    func cycle(_ index: Int, by offset: Int) {
        guard slots.indices.contains(index), slots[index].tabs.items.count > 1,
              let window = slots[index].tabs.step(offset) else { return }
        show(window)
    }

    /// Marks a tab as shown after you bring it forward with a click, Command-Tab or the Dock.
    func noteFocus(_ window: AXUIElement) {
        guard let index = index(of: window), slots[index].window != window else { return }
        slots[index].tabs.show(window)
        onChange()
    }

    /// After the shown tab leaves, the tab now in front shows.
    private func revealFront(_ index: Int) {
        if let front = WindowArranger.frontmost(of: slots[index].tabs.items) {
            slots[index].tabs.show(front)
        }
    }

    /// Moves every tab of a zone to the zone frame.
    private func snap(_ index: Int) {
        slots[index].quietUntil = Date().addingTimeInterval(0.4)
        for window in slots[index].tabs.items { WindowArranger.setFrame(window, slots[index].frame) }
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func observe(_ window: AXUIElement) {
        guard let pid = WindowArranger.pid(of: window) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let observer: AXObserver
        if let existing = observers[pid] {
            observer = existing
        } else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, refcon in
                guard let refcon else { return }
                Unmanaged<TileSession>.fromOpaque(refcon).takeUnretainedValue().changed(element, notification as String)
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observers[pid] = created
            observer = created
            // Clicks inside the app switch its focused window. Command-Tab is handled by AppModel.
            AXObserverAddNotification(created, AXUIElementCreateApplication(pid),
                                      kAXFocusedWindowChangedNotification as CFString, refcon)
        }
        for name in Self.notifications {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    private func unobserve(_ window: AXUIElement) {
        guard let pid = WindowArranger.pid(of: window), let observer = observers[pid] else { return }
        for name in Self.notifications {
            AXObserverRemoveNotification(observer, window, name as CFString)
        }
    }

    private func changed(_ element: AXUIElement, _ notification: String) {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            noteFocus(element)
            return
        case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification:
            remove(element)
            return
        default:
            break
        }
        // Only the shown tab drives resizing. Waiting tabs follow it.
        guard let index = index(of: element), slots[index].window == element else { return }
        // Ignore echoes of frames that Tessera set itself.
        guard Date() >= slots[index].quietUntil, let frame = WindowArranger.frame(of: element) else { return }
        let old = slots[index].frame
        // A drag only moves the window. The drop decides where it goes.
        guard abs(frame.width - old.width) > 1 || abs(frame.height - old.height) > 1 else { return }
        slots[index].frame = frame
        for tab in slots[index].tabs.items where tab != element { WindowArranger.setFrame(tab, frame) }

        var others: [Int: CGRect] = [:]
        for other in slots.indices where other != index { others[other] = slots[other].frame }
        for (other, target) in TileLinker.follow(old: old, new: frame, frames: others, gap: gap) {
            slots[other].frame = target.integral
            snap(other)
        }
        onChange()
    }
}

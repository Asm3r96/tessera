import AppKit
import ApplicationServices

/// Edge math for linked resizing. A moved edge is a line: every tile edge on that line follows it.
enum TileLinker {
    static let tolerance = 6.0
    static let minimumSize = 120.0

    static func follow(old: CGRect, new: CGRect, frames: [Int: CGRect], gap: Double) -> [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for (index, frame) in frames {
            var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
            if abs(new.maxX - old.maxX) > 1 {
                if near(minX, old.maxX + gap) { minX = new.maxX + gap }
                if near(maxX, old.maxX) { maxX = new.maxX }
            }
            if abs(new.minX - old.minX) > 1 {
                if near(maxX, old.minX - gap) { maxX = new.minX - gap }
                if near(minX, old.minX) { minX = new.minX }
            }
            if abs(new.maxY - old.maxY) > 1 {
                if near(minY, old.maxY + gap) { minY = new.maxY + gap }
                if near(maxY, old.maxY) { maxY = new.maxY }
            }
            if abs(new.minY - old.minY) > 1 {
                if near(maxY, old.minY - gap) { maxY = new.minY - gap }
                if near(minY, old.minY) { minY = new.minY }
            }
            let updated = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard updated != frame, updated.width >= minimumSize, updated.height >= minimumSize else { continue }
            result[index] = updated
        }
        return result
    }

    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < tolerance }
}

/// The applied mode on one screen: zone frames and the window in each zone.
/// Resizing a window moves its zone edges, and the neighbor zones follow.
final class TileSession {
    struct Slot {
        var frame: CGRect
        var window: AXUIElement?
        var quietUntil: Date
    }

    let screenID: CGDirectDisplayID
    let area: CGRect
    private(set) var slots: [Slot]
    private let gap: Double
    private var observers: [pid_t: AXObserver] = [:]
    private static let notifications = [kAXResizedNotification, kAXMovedNotification, kAXUIElementDestroyedNotification]

    init(_ placement: Placement, gap: Double) {
        screenID = placement.screenID
        area = placement.area
        self.gap = gap
        let quiet = Date().addingTimeInterval(0.5)
        slots = zip(placement.frames, placement.windows).map { Slot(frame: $0, window: $1, quietUntil: quiet) }
        for window in placement.windows.compactMap({ $0 }) { observe(window) }
    }

    deinit {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    var windows: [AXUIElement] { slots.compactMap(\.window) }

    func index(of window: AXUIElement) -> Int? {
        slots.firstIndex { slot in slot.window.map { CFEqual($0, window) } ?? false }
    }

    /// The zone under a point, or the nearest zone when the point is in a gap.
    func zone(at point: CGPoint) -> Int? {
        guard area.contains(point) else { return nil }
        return slots.indices.min { distance(point, slots[$0].frame) < distance(point, slots[$1].frame) }
    }

    /// Puts a window into a zone. A window from another zone swaps places with the occupant.
    /// A new window replaces the occupant, which stays where it is, behind.
    func place(_ window: AXUIElement, at index: Int) {
        let from = self.index(of: window)
        let occupant = slots[index].window
        if let from, from != index {
            slots[from].window = occupant
            snap(from)
        } else if from == nil {
            if let occupant { unobserve(occupant) }
            observe(window)
        }
        slots[index].window = window
        snap(index)
    }

    func remove(_ window: AXUIElement) {
        guard let index = index(of: window) else { return }
        unobserve(window)
        slots[index].window = nil
    }

    private func snap(_ index: Int) {
        guard let window = slots[index].window else { return }
        slots[index].quietUntil = Date().addingTimeInterval(0.4)
        WindowArranger.setFrame(window, slots[index].frame)
    }

    private func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func observe(_ window: AXUIElement) {
        guard let pid = WindowArranger.pid(of: window) else { return }
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
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
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
        guard let index = index(of: element) else { return }
        if notification == kAXUIElementDestroyedNotification as String {
            slots[index].window = nil
            return
        }
        // Ignore echoes of frames that Tessera set itself.
        guard Date() >= slots[index].quietUntil, let frame = WindowArranger.frame(of: element) else { return }
        let old = slots[index].frame
        // A drag only moves the window. The drop decides where it goes.
        guard abs(frame.width - old.width) > 1 || abs(frame.height - old.height) > 1 else { return }
        slots[index].frame = frame

        var others: [Int: CGRect] = [:]
        for other in slots.indices where other != index { others[other] = slots[other].frame }
        for (other, target) in TileLinker.follow(old: old, new: frame, frames: others, gap: gap) {
            slots[other].frame = target.integral
            snap(other)
        }
    }
}

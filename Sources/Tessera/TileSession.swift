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

/// Watches the windows of the last applied mode. When you resize one, its neighbors follow.
final class TileSession {
    private struct Tile {
        let window: AXUIElement
        let pid: pid_t
        var frame: CGRect
        var quietUntil: Date
    }

    private var tiles: [Tile] = []
    private let gap: Double
    private var observers: [pid_t: AXObserver] = [:]

    init(windows: [AXUIElement], gap: Double) {
        self.gap = gap
        let quiet = Date().addingTimeInterval(0.5)
        for window in windows {
            var pid: pid_t = 0
            guard AXUIElementGetPid(window, &pid) == .success,
                  let frame = WindowArranger.frame(of: window) else { continue }
            tiles.append(Tile(window: window, pid: pid, frame: frame, quietUntil: quiet))
        }
        for tile in tiles { observe(tile) }
    }

    deinit {
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    private func observe(_ tile: Tile) {
        let observer: AXObserver
        if let existing = observers[tile.pid] {
            observer = existing
        } else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, element, _, refcon in
                guard let refcon else { return }
                Unmanaged<TileSession>.fromOpaque(refcon).takeUnretainedValue().changed(element)
            }
            guard AXObserverCreate(tile.pid, callback, &created) == .success, let created else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observers[tile.pid] = created
            observer = created
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXResizedNotification, kAXMovedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, tile.window, name as CFString, refcon)
        }
    }

    private func changed(_ element: AXUIElement) {
        guard let index = tiles.firstIndex(where: { CFEqual($0.window, element) }) else { return }
        guard let frame = WindowArranger.frame(of: element) else {
            tiles.remove(at: index)
            return
        }
        let old = tiles[index].frame
        tiles[index].frame = frame
        // Ignore echoes of frames that Tessera set itself.
        guard Date() >= tiles[index].quietUntil else { return }
        // A plain move is not a resize.
        guard abs(frame.width - old.width) > 1 || abs(frame.height - old.height) > 1 else { return }

        var others: [Int: CGRect] = [:]
        for (i, tile) in tiles.enumerated() where i != index { others[i] = tile.frame }
        let quiet = Date().addingTimeInterval(0.3)
        for (i, target) in TileLinker.follow(old: old, new: frame, frames: others, gap: gap) {
            tiles[i].frame = target
            tiles[i].quietUntil = quiet
            WindowArranger.setFrame(tiles[i].window, target.integral)
        }
    }
}

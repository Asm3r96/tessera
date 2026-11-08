import AppKit
import TesseraCore
import ApplicationServices

/// Maps an Accessibility window to its CGWindowID. Private, but stable and used by Rectangle and AeroSpace.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// AppKit uses a bottom-left origin. Accessibility and CGWindowList use a top-left origin on the primary screen.
/// Tessera keeps every frame and point in top-left coordinates.
enum Screens {
    static func topLeft(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static var mouse: CGPoint {
        let point = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static func underMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    static func screen(id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }
}

/// Which windows go into which zone. Frames and stacks are in fill order: index 0 is the largest zone.
struct Placement {
    let screenID: CGDirectDisplayID
    /// The screen's visible frame.
    let area: CGRect
    let frames: [CGRect]
    /// The tabs of each zone. The first tab shows. An empty stack is an empty zone.
    let stacks: [[AXUIElement]]
}

enum WindowArranger {
    /// Plans a mode on a screen. Windows in `keep` come first, in their order. The other windows follow, frontmost first.
    /// When there are more windows than zones, the extra windows join the zones as tabs.
    static func plan(_ mode: Mode, on screen: NSScreen, gap: Double, keep: [AXUIElement]) -> Placement {
        let visible = Screens.topLeft(screen.visibleFrame)
        let area = visible.insetBy(dx: gap / 2, dy: gap / 2)
        let frames = mode.fillOrder.map { unit in
            CGRect(x: area.minX + unit.minX * area.width,
                   y: area.minY + unit.minY * area.height,
                   width: unit.width * area.width,
                   height: unit.height * area.height)
                .insetBy(dx: gap / 2, dy: gap / 2)
                .integral
        }
        let onScreen = frontToBackWindows(on: Screens.topLeft(screen.frame))
        let kept = keep.filter { window in onScreen.contains { CFEqual($0, window) } }
        let rest = onScreen.filter { window in !kept.contains { CFEqual($0, window) } }
        let ordered = kept + rest
        let stacks = Stacking.distribute(ordered.count, zones: frames.count).map { $0.map { ordered[$0] } }
        return Placement(screenID: screen.displayID, area: visible, frames: frames, stacks: stacks)
    }

    static func apply(_ placement: Placement) {
        for (stack, frame) in zip(placement.stacks, placement.frames) {
            for window in stack { setFrame(window, frame) }
        }
    }

    static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == .success ? id : nil
    }

    /// The window that is highest on screen.
    static func frontmost(of windows: [AXUIElement]) -> AXUIElement? {
        let ids = windows.map(windowID(of:))
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        for entry in info {
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let index = ids.firstIndex(of: number) else { continue }
            return windows[index]
        }
        return nil
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Brings a window to the front and makes its app active.
    static func focus(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        if let pid = pid(of: window) { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    /// Presses the window's close button, so the app can ask to save first. Returns false without a close button.
    static func close(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(value as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// The standard window at a point, for example the window whose title bar you press.
    static func window(at point: CGPoint) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        let window: AXUIElement
        if (role as? String) == (kAXWindowRole as String) {
            window = element
        } else {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &value) == .success,
                  let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            window = value as! AXUIElement
        }
        return isStandard(window) ? window : nil
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func pid(of window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(window, &pid) == .success ? pid : nil
    }

    /// Shown in the overlay only. Never saved.
    static func title(of window: AXUIElement) -> String {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
        return value as? String ?? ""
    }

    static func setFrame(_ window: AXUIElement, _ frame: CGRect) {
        var origin = frame.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Size, move, then size again: a window can refuse a size that crosses the screen edge at its old position.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
    }

    /// Standard windows whose center is on the screen, frontmost first.
    private static func frontToBackWindows(on screenFrame: CGRect) -> [AXUIElement] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var windowsByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var result: [AXUIElement] = []
        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  screenFrame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) else { continue }
            if windowsByPID[pid] == nil { windowsByPID[pid] = standardWindows(of: pid) }
            if let window = windowsByPID[pid]?[number] { result.append(window) }
        }
        return result
    }

    private static func standardWindows(of pid: pid_t) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [:] }
        var result: [CGWindowID: AXUIElement] = [:]
        for window in windows where isStandard(window) {
            if let id = windowID(of: window) { result[id] = window }
        }
        return result
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXStandardWindowSubrole as String)
    }
}

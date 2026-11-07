import AppKit
import ApplicationServices

/// Maps an Accessibility window to its CGWindowID. Private, but stable and used by Rectangle and AeroSpace.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowArranger {
    /// Arranges the windows on the screen under the mouse. Windows beyond the zone count stay where they are.
    /// Returns the windows it placed.
    @discardableResult
    static func arrange(_ mode: Mode, gap: Double) -> [AXUIElement] {
        guard let screen = targetScreen() else { return [] }
        let screenFrame = topLeftFrame(screen.frame)
        let area = topLeftFrame(screen.visibleFrame).insetBy(dx: gap / 2, dy: gap / 2)
        let windows = frontToBackWindows(on: screenFrame)
        for (window, unit) in zip(windows, mode.fillOrder) {
            let frame = CGRect(x: area.minX + unit.minX * area.width,
                               y: area.minY + unit.minY * area.height,
                               width: unit.width * area.width,
                               height: unit.height * area.height)
                .insetBy(dx: gap / 2, dy: gap / 2)
            setFrame(window, frame.integral)
        }
        return Array(windows.prefix(mode.fillOrder.count))
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

    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// AppKit uses a bottom-left origin. Accessibility and CGWindowList use a top-left origin on the primary screen.
    private static func topLeftFrame(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
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
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(window, &id) == .success { result[id] = window }
        }
        return result
    }

    private static func isStandard(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        return (subrole as? String) == (kAXStandardWindowSubrole as String)
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
}

import AppKit
import ApplicationServices
import TesseraCore

// Exercise the real TileSession with an in-memory window adapter.
// Synthetic AX elements never read or change windows on this Mac.
struct Placement {
    let screenID: CGDirectDisplayID
    let area: CGRect
    let frames: [CGRect]
    let stacks: [[AXUIElement]]
}

enum WindowArranger {
    static var frames: [AXUIElement: CGRect] = [:]
    static func setFrame(_ window: AXUIElement, _ frame: CGRect) { frames[window] = frame }
    static func frame(of window: AXUIElement) -> CGRect? { frames[window] }
    static func focus(_ window: AXUIElement) {}
    static func pid(of window: AXUIElement) -> pid_t? { nil }
    static func frontmost(of windows: [AXUIElement]) -> AXUIElement? { windows.first }
}

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}

let first = AXUIElementCreateApplication(100001)
let tab = AXUIElementCreateApplication(100002)
let second = AXUIElementCreateApplication(100003)
let outside = AXUIElementCreateApplication(100004)
// A secondary display to the left of the primary display.
let area = CGRect(x: -1440, y: 25, width: 1440, height: 875)
let left = CGRect(x: -1432, y: 33, width: 704, height: 859)
let right = CGRect(x: -720, y: 33, width: 712, height: 859)
let placement = Placement(screenID: 1, area: area, frames: [left, right], stacks: [[first, tab], [second]])
let session = TileSession(placement, gap: 8)
WindowArranger.frames = [first: left, tab: left, second: right]

session.toggleFocus(first)
check(session.focusedWindow == first, "First window enters focus")
check(WindowArranger.frames[first] == area, "Focus uses the usable screen area in top-left coordinates")
check(session.slots.map(\.frame) == [left, right], "Focus preserves zone frames")
check(WindowArranger.frames[tab] == left, "Waiting tab stays in its zone")
check(WindowArranger.frames[second] == right, "Neighbor stays in its zone")
session.toggleFocus(first)
check(session.focusedWindow == nil, "Second press ends focus")
check(WindowArranger.frames[first] == left, "Second press restores the exact zone")

session.toggleFocus(first)
session.toggleFocus(second)
check(session.focusedWindow == second, "Another window can take focus")
check(WindowArranger.frames[first] == left, "Previous focused window is restored")
check(WindowArranger.frames[second] == area, "New focused window expands")
session.noteFocus(first)
check(session.focusedWindow == nil, "Switching to another tiled window ends focus")
check(WindowArranger.frames[second] == right, "Switching restores the focused window")

session.toggleFocus(first)
session.cycle(0, by: 1)
check(session.focusedWindow == nil, "Cycling tabs ends focus")
check(session.slots[0].window == tab, "Next tab shows")
check(WindowArranger.frames[first] == left && WindowArranger.frames[tab] == left, "Both tabs retain their zone")

session.toggleFocus(tab)
WindowArranger.frames[tab] = area.offsetBy(dx: 100, dy: 50)
session.place(tab, at: 0)
check(session.focusedWindow == nil, "Dropping ends focus")
check(WindowArranger.frames[tab] == left, "Dropping back restores the zone")

session.toggleFocus(tab)
session.remove(tab)
check(session.focusedWindow == nil, "Closing or minimizing clears focus")
check(session.slots[0].window == first, "Remaining tab shows after removal")
check(session.slots[0].frame == left, "Removal preserves the zone")

session.toggleFocus(outside)
check(session.focusedWindow == nil, "Untiled windows cannot enter focus")
session.toggleFocus(first)
session.place(second, at: 0)
check(session.focusedWindow == nil, "A swap ends focus")
check(WindowArranger.frames[first] == right, "A swapped window gets its new zone")
check(WindowArranger.frames[second] == left, "Swap target gets the saved zone")

session.toggleFocus(second)
session.addTab(outside, at: 0)
check(session.focusedWindow == nil, "Adding a tab ends focus")
check(WindowArranger.frames[second] == left, "Adding a tab restores the focused window")
check(WindowArranger.frames[outside] == left, "New tab uses the zone, not the focus frame")

print("All \(checks) focus checks passed.")

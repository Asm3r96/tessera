// Logic checks for TesseraCore. Run: swift run TesseraChecks
// XCTest and Swift Testing need Xcode, so these checks run as a plain executable.
import CoreGraphics
import Foundation
import TesseraCore

var failures = 0
var count = 0

func check(_ condition: Bool, _ name: String, file: String = #file, line: Int = #line) {
    count += 1
    if !condition {
        failures += 1
        print("FAIL \(name) (line \(line))")
    }
}

func near(_ a: CGRect, _ b: CGRect) -> Bool {
    abs(a.minX - b.minX) < 0.0001 && abs(a.minY - b.minY) < 0.0001
        && abs(a.width - b.width) < 0.0001 && abs(a.height - b.height) < 0.0001
}

// Zones
let halves = Mode(name: "Halves", columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 1)])
check(halves.zones.count == 2, "halves has two zones")
check(near(halves.zones[0], CGRect(x: 0, y: 0, width: 0.5, height: 1)), "left half")
check(near(halves.zones[1], CGRect(x: 0.5, y: 0, width: 0.5, height: 1)), "right half")

let stack = Mode(name: "Main + Stack", columns: [Column(weight: 2, rows: 1), Column(weight: 1, rows: 2)])
check(stack.zones.count == 3, "main + stack has three zones")
check(near(stack.zones[2], CGRect(x: 2.0 / 3, y: 0.5, width: 1.0 / 3, height: 0.5)), "bottom of stack")
let covered = stack.zones.map { $0.width * $0.height }.reduce(0, +)
check(abs(covered - 1) < 0.0001, "zones cover the whole area")

// Fill order: the largest zone first, then left to right, top to bottom.
let focus = Mode(name: "Focus", columns: [Column(weight: 1, rows: 1), Column(weight: 2, rows: 1), Column(weight: 1, rows: 1)])
check(near(focus.fillOrder[0], focus.zones[1]), "the wide middle zone fills first")
check(near(focus.fillOrder[1], focus.zones[0]), "then the left zone")
check(near(focus.fillOrder[2], focus.zones[2]), "then the right zone")

let empty = Mode(name: "Zero", columns: [Column(weight: 0, rows: 0)])
check(empty.zones.count == 1, "zero rows count as one row")

// Saved modes survive encoding.
let data = try JSONEncoder().encode(Mode.defaults)
let decoded = try JSONDecoder().decode([Mode].self, from: data)
check(decoded == Mode.defaults, "modes round-trip through JSON")

// Linked resize: two columns with an 8 pt gap.
let gap = 8.0
let left = CGRect(x: 0, y: 0, width: 496, height: 800)
let right = CGRect(x: 504, y: 0, width: 496, height: 800)
let wider = CGRect(x: 0, y: 0, width: 596, height: 800)
let followed = TileLinker.follow(old: left, new: wider, frames: [1: right], gap: gap)
check(followed[1] == CGRect(x: 604, y: 0, width: 396, height: 800), "right column follows the moved edge")

let moved = TileLinker.follow(old: left, new: left.offsetBy(dx: 0, dy: 0), frames: [1: right], gap: gap)
check(moved.isEmpty, "no change, no follow")

let tooFar = CGRect(x: 0, y: 0, width: 950, height: 800)
check(TileLinker.follow(old: left, new: tooFar, frames: [1: right], gap: gap).isEmpty, "a neighbor never shrinks below the minimum")

// Stacked rows: dragging the split between top and bottom.
let top = CGRect(x: 504, y: 0, width: 496, height: 396)
let bottom = CGRect(x: 504, y: 404, width: 496, height: 396)
let taller = CGRect(x: 504, y: 0, width: 496, height: 496)
let rows = TileLinker.follow(old: top, new: taller, frames: [0: left, 2: bottom], gap: gap)
check(rows[2] == CGRect(x: 504, y: 504, width: 496, height: 296), "bottom row follows")
check(rows[0] == nil, "the left column is not on that edge")

// Three columns: the middle edge moves both neighbors that touch it.
let a = CGRect(x: 0, y: 0, width: 400, height: 800)
let b = CGRect(x: 408, y: 0, width: 292, height: 800)
let c = CGRect(x: 708, y: 0, width: 292, height: 800)
let bWider = CGRect(x: 358, y: 0, width: 342, height: 800)
let three = TileLinker.follow(old: b, new: bWider, frames: [0: a, 2: c], gap: gap)
check(three[0] == CGRect(x: 0, y: 0, width: 350, height: 800), "left column shrinks")
check(three[2] == nil, "right column does not move")

// Versions
check(Version("0.2.0")! > Version("0.1.1")!, "0.2.0 is newer than 0.1.1")
check(Version("v0.10.0")! > Version("0.9.9")!, "numbers compare as numbers, not text")
check(Version("1.2") == Version("1.2.0"), "missing parts count as zero")
check(Version("v1.0.0")?.description == "1.0.0", "a leading v is dropped")
check(Version("0.1.0-3-g9ab980c") == nil, "a source build is not a release")
check(Version("dev") == nil, "dev is not a release")
check(Version("1..2") == nil, "an empty part is rejected")
check(Version("1.2.3.4") == nil, "four parts are rejected")
check(!(Version("0.2.0")! > Version("0.2.0")!), "the same version is not an update")

// Release responses from GitHub
func payload(tag: String, asset: String = "Tessera.zip", url: String = "https://github.com/Asm3r96/tessera/releases/download/v0.2.0/Tessera.zip") -> Data {
    Data("""
    {"tag_name": "\(tag)", "html_url": "https://github.com/Asm3r96/tessera/releases/tag/\(tag)",
     "assets": [{"name": "\(asset)", "browser_download_url": "\(url)"}]}
    """.utf8)
}
let parsed = Release.parse(payload(tag: "v0.2.0"))
check(parsed?.version == Version("0.2.0"), "release version comes from the tag")
check(parsed?.download.lastPathComponent == "Tessera.zip", "release download is the zip")
check(Release.parse(payload(tag: "v0.2.0", asset: "Other.zip")) == nil, "a release without Tessera.zip is ignored")
check(Release.parse(payload(tag: "nightly")) == nil, "a tag that is not a version is ignored")
check(Release.parse(payload(tag: "v0.2.0", url: "http://example.com/Tessera.zip")) == nil, "a plain http download is refused")
check(Release.parse(Data("not json".utf8)) == nil, "a broken response is ignored")
if let path = ProcessInfo.processInfo.environment["TESSERA_RELEASE_JSON"],
   let live = FileManager.default.contents(atPath: path) {
    check(Release.parse(live) != nil, "the live GitHub response parses")
}

// Tabs
var tabs = TabStack(["Mail"])
tabs.add("Terminal")
check(tabs.items == ["Mail", "Terminal"] && tabs.shown == "Terminal", "a new tab is added last and shows")
tabs.add("Mail")
check(tabs.items.count == 2 && tabs.shown == "Mail", "adding a tab again only shows it")
tabs.add("Notes")
tabs.show("Terminal")
check(tabs.step(1) == "Notes", "next tab")
check(tabs.step(1) == "Mail", "next tab wraps to the first")
check(tabs.step(-1) == "Notes", "previous tab wraps to the last")
tabs.remove("Notes")
check(tabs.shown == "Terminal", "removing the last shown tab shows the one before it")
tabs.show("Mail")
tabs.remove("Mail")
check(tabs.shown == "Terminal" && tabs.items == ["Terminal"], "removing the first shown tab shows the next one")
tabs.add("Notes")
tabs.show("Terminal")
tabs.remove("Notes")
check(tabs.shown == "Terminal", "removing a waiting tab keeps the shown tab")
tabs.replace("Terminal", with: "Safari")
check(tabs.items == ["Safari"] && tabs.shown == "Safari", "replace keeps the place and the shown state")
tabs.remove("Safari")
check(tabs.shown == nil && tabs.items.isEmpty, "the last tab leaves an empty zone")
check(!tabs.remove("Safari"), "removing a missing tab does nothing")
var noTabs = TabStack<String>()
check(noTabs.step(1) == nil, "an empty zone has no next tab")
check(Stacking.distribute(2, zones: 3) == [[0], [1], []], "fewer windows than zones leaves zones empty")
check(Stacking.distribute(5, zones: 2) == [[0, 2, 4], [1, 3]], "extra windows become tabs, zone by zone")
check(Stacking.distribute(3, zones: 0).isEmpty, "no zones, no stacks")

// Drop targets
let wide = CGRect(x: 0, y: 0, width: 1000, height: 800)
check(near(DropTarget.rect(in: wide), CGRect(x: 200, y: 160, width: 600, height: 480)), "the target is the center 60%")
let narrow = CGRect(x: 100, y: 0, width: 250, height: 200)
check(near(DropTarget.rect(in: narrow), CGRect(x: 135, y: 30, width: 180, height: 140)), "a small zone keeps a minimum target")
let tiny = CGRect(x: 0, y: 0, width: 150, height: 100)
check(near(DropTarget.rect(in: tiny), tiny), "the target never grows past its zone")
check(!DropTarget.rect(in: wide).contains(CGPoint(x: 50, y: 400)), "a drop near the edge misses the target")

let start = Date()
var arming = DropArming()
arming.update(2, at: start)
check(arming.armed(at: start.addingTimeInterval(0.1)) == nil, "a quick pass does not arm the target")
check(arming.armed(at: start.addingTimeInterval(0.35)) == 2, "a rest arms the target")
arming.update(2, at: start.addingTimeInterval(0.4))
check(arming.armed(at: start.addingTimeInterval(0.45)) == 2, "staying on the target keeps it armed")
arming.update(1, at: start.addingTimeInterval(0.5))
check(arming.armed(at: start.addingTimeInterval(0.6)) == nil, "a new target starts the wait again")
arming.update(nil, at: start.addingTimeInterval(0.7))
check(arming.armed(at: start.addingTimeInterval(2)) == nil, "off every target, nothing is armed")

print(failures == 0 ? "All \(count) checks passed." : "\(failures) of \(count) checks failed.")
exit(failures == 0 ? 0 : 1)

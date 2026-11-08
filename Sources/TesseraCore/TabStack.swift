/// The windows that share one zone, like tabs. One of them shows; the others wait behind it at the same size.
public struct TabStack<Item: Equatable> {
    public private(set) var items: [Item]
    private var shownIndex: Int?

    public init(_ items: [Item] = []) {
        self.items = items
        shownIndex = items.isEmpty ? nil : 0
    }

    /// The window that shows in the zone.
    public var shown: Item? { shownIndex.map { items[$0] } }

    public func contains(_ item: Item) -> Bool { items.contains(item) }

    /// Adds a window as the last tab and shows it. A window that is already a tab only shows.
    public mutating func add(_ item: Item) {
        if let index = items.firstIndex(of: item) {
            shownIndex = index
            return
        }
        items.append(item)
        shownIndex = items.count - 1
    }

    /// Removes a tab. When it was showing, the next tab shows, or the previous one at the end.
    @discardableResult
    public mutating func remove(_ item: Item) -> Bool {
        guard let index = items.firstIndex(of: item) else { return false }
        items.remove(at: index)
        guard !items.isEmpty, let shown = shownIndex else {
            shownIndex = items.isEmpty ? nil : shownIndex
            return true
        }
        if shown == index {
            shownIndex = min(index, items.count - 1)
        } else if shown > index {
            shownIndex = shown - 1
        }
        return true
    }

    /// Puts `new` in the tab of `old`. The tab keeps its position and stays shown if it was.
    public mutating func replace(_ old: Item, with new: Item) {
        guard let index = items.firstIndex(of: old) else { return }
        items[index] = new
    }

    @discardableResult
    public mutating func show(_ item: Item) -> Bool {
        guard let index = items.firstIndex(of: item) else { return false }
        shownIndex = index
        return true
    }

    /// Shows the tab `offset` places away. Wraps at both ends.
    @discardableResult
    public mutating func step(_ offset: Int) -> Item? {
        guard !items.isEmpty else { return nil }
        let current = shownIndex ?? 0
        let count = items.count
        shownIndex = ((current + offset) % count + count) % count
        return shown
    }
}

public enum Stacking {
    /// Splits windows, front to back, over zones. Each zone gets one window first.
    /// Extra windows join the zones in turn as tabs. Returns window indices per zone.
    public static func distribute(_ count: Int, zones: Int) -> [[Int]] {
        guard zones > 0 else { return [] }
        var result = Array(repeating: [Int](), count: zones)
        for index in 0..<count { result[index % zones].append(index) }
        return result
    }
}

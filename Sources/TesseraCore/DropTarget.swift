import CoreGraphics
import Foundation

/// The part of a zone that accepts drops: a box in its center. Drops elsewhere leave the window floating.
public enum DropTarget {
    public static let fraction = 0.6
    public static let minimumSize = CGSize(width: 180, height: 140)

    /// A centered box with `fraction` of the zone's width and height, at least `minimumSize`, never larger than the zone.
    public static func rect(in zone: CGRect) -> CGRect {
        let width = min(zone.width, max(zone.width * fraction, minimumSize.width))
        let height = min(zone.height, max(zone.height * fraction, minimumSize.height))
        return CGRect(x: zone.midX - width / 2, y: zone.midY - height / 2, width: width, height: height)
    }
}

/// A drop target counts only after the pointer rests on it, so a quick drag across the screen never triggers it.
public struct DropArming {
    public static let delay: TimeInterval = 0.3
    public private(set) var target: Int?
    private var since: Date?

    public init() {}

    /// Call on every pointer move with the target under the pointer, or nil.
    public mutating func update(_ target: Int?, at time: Date) {
        guard target != self.target else { return }
        self.target = target
        since = target == nil ? nil : time
    }

    /// The target, once the pointer has rested on it for `delay`.
    public func armed(at time: Date) -> Int? {
        guard let target, let since, time.timeIntervalSince(since) >= Self.delay else { return nil }
        return target
    }
}

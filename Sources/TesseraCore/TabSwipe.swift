import CoreGraphics

/// Turns raw trackpad touch frames into one tab step per three-finger horizontal swipe.
/// Points are normalized to the trackpad: x grows to the right, y grows upward.
public struct TabSwipe {
    public static let fingers = 3
    /// Part of the trackpad width the fingers must travel before the tab switches.
    public static let distance = 0.12

    private var start: CGPoint?
    private var fired = false

    public init() {}

    /// Returns 1 for a left swipe (next tab) or -1 for a right swipe (previous tab), once per gesture.
    public mutating func update(_ touches: [CGPoint]) -> Int? {
        guard touches.count == Self.fingers else {
            start = nil
            fired = false
            return nil
        }
        let count = CGFloat(touches.count)
        let center = CGPoint(x: touches.map(\.x).reduce(0, +) / count, y: touches.map(\.y).reduce(0, +) / count)
        guard let start else {
            self.start = center
            return nil
        }
        let dx = center.x - start.x
        let dy = center.y - start.y
        guard !fired, abs(dx) >= Self.distance, abs(dx) > 2 * abs(dy) else { return nil }
        fired = true
        return dx < 0 ? 1 : -1
    }
}

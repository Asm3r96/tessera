/// Maps a discrete horizontal page swipe to one tab step.
public enum TabSwipe {
    public static func offset(x: Double, y: Double) -> Int? {
        guard x.isFinite, y.isFinite, abs(x) > abs(y) else { return nil }
        // AppKit reports a left swipe as positive deltaX.
        return x > 0 ? 1 : -1
    }
}

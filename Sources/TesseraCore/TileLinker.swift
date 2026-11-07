import CoreGraphics

/// Edge math for linked resizing. A moved edge is a line: every tile edge on that line follows it.
public enum TileLinker {
    public static let tolerance = 6.0
    public static let minimumSize = 120.0

    public static func follow(old: CGRect, new: CGRect, frames: [Int: CGRect], gap: Double) -> [Int: CGRect] {
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

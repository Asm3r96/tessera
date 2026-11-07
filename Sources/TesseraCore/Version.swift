/// A release version such as 1.2.3. Source builds such as 0.1.0-3-gabc1234 are not release versions.
public struct Version: Comparable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts 1, 1.2, 1.2.3, with or without a leading "v". Returns nil for anything else.
    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts + Array(repeating: 0, count: 3 - parts.count)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }
}

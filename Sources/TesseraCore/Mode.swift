import CoreGraphics
import Foundation

public struct Column: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var weight: Double
    public var rows: Int

    public init(weight: Double, rows: Int) {
        self.weight = weight
        self.rows = rows
    }
}

/// A saved layout: columns with relative widths, each split into equal rows.
public struct Mode: Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var columns: [Column]

    public init(name: String, columns: [Column]) {
        self.name = name
        self.columns = columns
    }

    /// Zones as unit rects with a top-left origin, left to right, top to bottom.
    public var zones: [CGRect] {
        let total = max(columns.map(\.weight).reduce(0, +), 0.0001)
        var x = 0.0
        var result: [CGRect] = []
        for column in columns {
            let width = column.weight / total
            let rows = max(column.rows, 1)
            let height = 1.0 / Double(rows)
            for row in 0..<rows {
                result.append(CGRect(x: x, y: Double(row) * height, width: width, height: height))
            }
            x += width
        }
        return result
    }

    /// The order windows fill zones: the frontmost window gets the largest zone.
    public var fillOrder: [CGRect] {
        zones.enumerated().sorted { a, b in
            let areaA = a.element.width * a.element.height
            let areaB = b.element.width * b.element.height
            if abs(areaA - areaB) > 0.0001 { return areaA > areaB }
            return a.offset < b.offset
        }.map(\.element)
    }

    public static let defaults: [Mode] = [
        Mode(name: "Halves", columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 1)]),
        Mode(name: "Focus", columns: [Column(weight: 1, rows: 1), Column(weight: 2, rows: 1), Column(weight: 1, rows: 1)]),
        Mode(name: "Main + Stack", columns: [Column(weight: 2, rows: 1), Column(weight: 1, rows: 2)]),
        Mode(name: "Grid", columns: [Column(weight: 1, rows: 2), Column(weight: 1, rows: 2)]),
        Mode(name: "Thirds", columns: [Column(weight: 1, rows: 1), Column(weight: 1, rows: 1), Column(weight: 1, rows: 1)]),
    ]
}

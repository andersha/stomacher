import Foundation

struct GridCoordinate: Codable, Hashable, Identifiable {
    var x: Int
    var y: Int

    var id: String { "\(x):\(y)" }
}

struct GridBounds: Equatable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

struct PatternDocument: Codable, Identifiable {
    var id: UUID
    var title: String
    var technique: PatternTechnique
    var width: Int
    var height: Int
    var palette: [PaletteSwatch]
    var cells: [GridCoordinate: UUID]
    var outlineCells: Set<GridCoordinate>
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case technique
        case width
        case height
        case palette
        case cells
        case outlineCells
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String = "Ny bringeduk",
        technique: PatternTechnique = .beads,
        width: Int = 180,
        height: Int = 120,
        palette: [PaletteSwatch] = PaletteSwatch.defaultPalette,
        cells: [GridCoordinate: UUID] = [:],
        outlineCells: Set<GridCoordinate> = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.technique = technique
        self.width = width
        self.height = height
        self.palette = palette
        self.cells = cells
        self.outlineCells = outlineCells
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        technique = try container.decode(PatternTechnique.self, forKey: .technique)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        palette = try container.decode([PaletteSwatch].self, forKey: .palette)
        cells = try container.decode([GridCoordinate: UUID].self, forKey: .cells)
        outlineCells = try container.decodeIfPresent(Set<GridCoordinate>.self, forKey: .outlineCells) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(technique, forKey: .technique)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(palette, forKey: .palette)
        try container.encode(cells, forKey: .cells)
        try container.encode(outlineCells, forKey: .outlineCells)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var usedSwatches: [PaletteSwatch] {
        let ids = Set(cells.values)
        return palette.filter { ids.contains($0.id) }
    }

    var hasCustomOutline: Bool {
        !outlineCells.isEmpty
    }

    var fullBounds: GridBounds {
        GridBounds(minX: 0, minY: 0, maxX: width - 1, maxY: height - 1)
    }

    var printableBounds: GridBounds {
        activePatternArea()?.bounds ?? fullBounds
    }

    func isWithinPatternArea(_ coordinate: GridCoordinate) -> Bool {
        guard let area = activePatternArea() else { return true }
        return area.contains(coordinate)
    }

    func activePatternArea() -> Set<GridCoordinate>? {
        guard hasCustomOutline else { return nil }

        let outside = outsideOutlineCells()
        var area = Set<GridCoordinate>()
        area.reserveCapacity(width * height - outside.count)

        for y in 0..<height {
            for x in 0..<width {
                let coordinate = GridCoordinate(x: x, y: y)
                if !outside.contains(coordinate) {
                    area.insert(coordinate)
                }
            }
        }

        return area.count > outlineCells.count ? area : nil
    }

    func swatch(for id: UUID) -> PaletteSwatch? {
        palette.first { $0.id == id }
    }

    private func outsideOutlineCells() -> Set<GridCoordinate> {
        var outside = Set<GridCoordinate>()
        var queue: [GridCoordinate] = []
        var queueIndex = 0

        func enqueue(_ coordinate: GridCoordinate) {
            guard coordinate.x >= 0, coordinate.x < width, coordinate.y >= 0, coordinate.y < height else { return }
            guard !outlineCells.contains(coordinate), !outside.contains(coordinate) else { return }
            outside.insert(coordinate)
            queue.append(coordinate)
        }

        for x in 0..<width {
            enqueue(GridCoordinate(x: x, y: 0))
            enqueue(GridCoordinate(x: x, y: height - 1))
        }

        for y in 0..<height {
            enqueue(GridCoordinate(x: 0, y: y))
            enqueue(GridCoordinate(x: width - 1, y: y))
        }

        while queueIndex < queue.count {
            let coordinate = queue[queueIndex]
            queueIndex += 1

            enqueue(GridCoordinate(x: coordinate.x + 1, y: coordinate.y))
            enqueue(GridCoordinate(x: coordinate.x - 1, y: coordinate.y))
            enqueue(GridCoordinate(x: coordinate.x, y: coordinate.y + 1))
            enqueue(GridCoordinate(x: coordinate.x, y: coordinate.y - 1))
        }

        return outside
    }
}

extension Sequence where Element == GridCoordinate {
    var bounds: GridBounds? {
        var iterator = makeIterator()
        guard let first = iterator.next() else { return nil }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        while let coordinate = iterator.next() {
            minX = Swift.min(minX, coordinate.x)
            maxX = Swift.max(maxX, coordinate.x)
            minY = Swift.min(minY, coordinate.y)
            maxY = Swift.max(maxY, coordinate.y)
        }

        return GridBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }
}

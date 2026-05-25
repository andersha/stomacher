import Foundation

struct GridCoordinate: Codable, Hashable, Identifiable {
    var x: Int
    var y: Int

    var id: String { "\(x):\(y)" }

    func offsetBy(x deltaX: Int, y deltaY: Int) -> GridCoordinate {
        GridCoordinate(x: x + deltaX, y: y + deltaY)
    }
}

struct GridBounds: Equatable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

enum SewingStartCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Oppe til venstre"
        case .topRight: "Oppe til høyre"
        case .bottomLeft: "Nede til venstre"
        case .bottomRight: "Nede til høyre"
        }
    }

    var horizontalStep: Int {
        switch self {
        case .topLeft, .bottomLeft: 1
        case .topRight, .bottomRight: -1
        }
    }

    var verticalStep: Int {
        switch self {
        case .topLeft, .topRight: 1
        case .bottomLeft, .bottomRight: -1
        }
    }
}

struct SewingProgress: Codable, Equatable {
    var startCorner: SewingStartCorner
    var current: GridCoordinate
}

struct PatternDocument: Codable, Identifiable {
    static let oldestSupportedFileFormatVersion = 1
    static let currentFileFormatVersion = 1

    var fileFormatVersion: Int
    var id: UUID
    var title: String
    var patternDescription: String
    var technique: PatternTechnique
    var width: Int
    var height: Int
    var gridBlockSize: Int
    var paletteID: UUID
    var paletteName: String
    var palette: [PaletteSwatch]
    var cells: [GridCoordinate: UUID]
    var outlineCells: Set<GridCoordinate>
    var hideUnusedArea: Bool
    var isProtected: Bool
    var sewingProgress: SewingProgress?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case fileFormatVersion
        case id
        case title
        case patternDescription = "description"
        case technique
        case width
        case height
        case gridBlockSize
        case paletteID
        case paletteName
        case palette
        case cells
        case outlineCells
        case hideUnusedArea
        case isProtected
        case sewingProgress
        case createdAt
        case updatedAt
    }

    init(
        fileFormatVersion: Int = Self.currentFileFormatVersion,
        id: UUID = UUID(),
        title: String = "Ny bringeduk",
        patternDescription: String = "",
        technique: PatternTechnique = .beads,
        width: Int = 180,
        height: Int = 120,
        gridBlockSize: Int = 10,
        paletteID: UUID = PatternPalette.standardID,
        paletteName: String = PatternPalette.standardName,
        palette: [PaletteSwatch] = PaletteSwatch.defaultPalette,
        cells: [GridCoordinate: UUID] = [:],
        outlineCells: Set<GridCoordinate> = [],
        hideUnusedArea: Bool = false,
        isProtected: Bool = false,
        sewingProgress: SewingProgress? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.fileFormatVersion = fileFormatVersion
        self.id = id
        self.title = title
        self.patternDescription = patternDescription
        self.technique = technique
        self.width = width
        self.height = height
        self.gridBlockSize = Self.normalizedGridBlockSize(gridBlockSize)
        self.paletteID = paletteID
        self.paletteName = paletteName
        self.palette = palette
        self.cells = cells
        self.outlineCells = outlineCells
        self.hideUnusedArea = hideUnusedArea
        self.isProtected = isProtected
        self.sewingProgress = sewingProgress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileFormatVersion = try container.decodeIfPresent(Int.self, forKey: .fileFormatVersion) ?? 1

        guard (Self.oldestSupportedFileFormatVersion...Self.currentFileFormatVersion).contains(fileFormatVersion) else {
            throw DecodingError.dataCorruptedError(
                forKey: .fileFormatVersion,
                in: container,
                debugDescription: "Unsupported .stom file format version \(fileFormatVersion). This app supports versions \(Self.oldestSupportedFileFormatVersion)-\(Self.currentFileFormatVersion)."
            )
        }

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        patternDescription = try container.decodeIfPresent(String.self, forKey: .patternDescription) ?? ""
        technique = try container.decode(PatternTechnique.self, forKey: .technique)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        gridBlockSize = Self.normalizedGridBlockSize(try container.decodeIfPresent(Int.self, forKey: .gridBlockSize) ?? 10)
        paletteID = try container.decodeIfPresent(UUID.self, forKey: .paletteID) ?? PatternPalette.standardID
        paletteName = try container.decodeIfPresent(String.self, forKey: .paletteName) ?? PatternPalette.standardName
        palette = try container.decode([PaletteSwatch].self, forKey: .palette)
        cells = try container.decode([GridCoordinate: UUID].self, forKey: .cells)
        outlineCells = try container.decodeIfPresent(Set<GridCoordinate>.self, forKey: .outlineCells) ?? []
        hideUnusedArea = try container.decodeIfPresent(Bool.self, forKey: .hideUnusedArea) ?? false
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
        sewingProgress = try container.decodeIfPresent(SewingProgress.self, forKey: .sewingProgress)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFileFormatVersion, forKey: .fileFormatVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(patternDescription, forKey: .patternDescription)
        try container.encode(technique, forKey: .technique)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(gridBlockSize, forKey: .gridBlockSize)
        try container.encode(paletteID, forKey: .paletteID)
        try container.encode(paletteName, forKey: .paletteName)
        try container.encode(palette, forKey: .palette)
        try container.encode(cells, forKey: .cells)
        try container.encode(outlineCells, forKey: .outlineCells)
        try container.encode(hideUnusedArea, forKey: .hideUnusedArea)
        try container.encode(isProtected, forKey: .isProtected)
        try container.encodeIfPresent(sewingProgress, forKey: .sewingProgress)
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

    func sewingTraversal(from startCorner: SewingStartCorner) -> [GridCoordinate] {
        let bounds = printableBounds
        let patternArea = activePatternArea()
        let yValues = stride(
            from: startCorner.verticalStep > 0 ? bounds.minY : bounds.maxY,
            through: startCorner.verticalStep > 0 ? bounds.maxY : bounds.minY,
            by: startCorner.verticalStep
        )
        var traversal: [GridCoordinate] = []
        traversal.reserveCapacity(bounds.width * bounds.height)

        for (rowIndex, y) in yValues.enumerated() {
            let horizontalStep = rowIndex.isMultiple(of: 2) ? startCorner.horizontalStep : -startCorner.horizontalStep
            let xStart = horizontalStep > 0 ? bounds.minX : bounds.maxX
            let xEnd = horizontalStep > 0 ? bounds.maxX : bounds.minX

            for x in stride(from: xStart, through: xEnd, by: horizontalStep) {
                let coordinate = GridCoordinate(x: x, y: y)
                guard patternArea?.contains(coordinate) ?? true else { continue }
                traversal.append(coordinate)
            }
        }

        return traversal
    }

    static func normalizedGridBlockSize(_ value: Int) -> Int {
        min(20, max(2, value))
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

extension String {
    var stomFileName: String {
        let illegalCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: illegalCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let baseName = cleaned.isEmpty ? "bringeduk" : cleaned
        return baseName.hasSuffix(".stom") ? baseName : "\(baseName).stom"
    }
}

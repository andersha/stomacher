import Foundation

// MARK: - Prosedyrebasert mønstergenerering
//
// Denne modulen lager nye mønstre ut fra et eksisterende motiv ved hjelp av
// rene, geometriske operasjoner (speiling, rotasjon, flislegging). Den er
// bevisst holdt tilstandsløs og uten avhengighet til `PatternStore` eller
// SwiftUI, slik at logikken er lett å lese, teste og forfine isolert etter hvert
// som vi gjør oss erfaringer med hva som gir gode bringeduk-mønstre.
//
// All matematikk jobber på `PatternMotif` — en samling utfylte ruter normalisert
// slik at bounding-boksen starter i (0,0). `PatternStore` står for å hente
// motivet fra en markering og for å plassere resultatet på rutenettet.

/// Et motiv hentet fra en markering: utfylte ruter normalisert slik at
/// bounding-boksen starter i (0,0). Dette er "byggeklossen" all generering
/// jobber på.
struct PatternMotif: Equatable {
    /// Ruter med farge, der nøklene er relative til motivets eget (0,0)-hjørne.
    var cells: [GridCoordinate: UUID]
    var width: Int
    var height: Int

    var isEmpty: Bool { cells.isEmpty }

    init(cells: [GridCoordinate: UUID], width: Int, height: Int) {
        self.cells = cells
        self.width = width
        self.height = height
    }

    /// Lager et motiv fra vilkårlige celler og normaliserer det til (0,0).
    init(cells: [GridCoordinate: UUID]) {
        self = PatternGenerator.normalized(cells)
    }
}

/// Symmetri-varianter som lager én sammensatt blokk fra ett motiv.
enum SymmetryKind: String, CaseIterable, Identifiable {
    /// Motiv + horisontal speiling ved siden av (dobbel bredde).
    case mirrorHorizontal
    /// Motiv + vertikal speiling under (dobbel høyde).
    case mirrorVertical
    /// 4 kopier rotert 90° rundt et felles senter (pinwheel/rosett).
    case rotate4
    // 4-folds speiling til kvadrat dekkes av `completeQuarterAsSquare` i
    // transform-panelet, og er bevisst utelatt her for å unngå duplisering.
    // (kaleidoskop/8-folds vurderes i en senere iterasjon)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mirrorHorizontal: "Speil til par (vannrett)"
        case .mirrorVertical: "Speil til par (loddrett)"
        case .rotate4: "Roter til rosett"
        }
    }

    var systemImage: String {
        switch self {
        case .mirrorHorizontal: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        case .mirrorVertical: "arrow.up.and.down.righttriangle.up.righttriangle.down"
        case .rotate4: "arrow.triangle.2.circlepath"
        }
    }
}

/// Parametre for flislegging av et motiv i et rutemønster.
struct TilingOptions: Equatable {
    var columns: Int
    var rows: Int
    /// Mellomrom i ruter mellom fliser, vannrett og loddrett.
    var spacingX: Int
    var spacingY: Int
    /// Speil annenhver kolonne/rad for sømløse bord og speilsymmetriske flater.
    var flipAlternateColumns: Bool
    var flipAlternateRows: Bool

    init(
        columns: Int,
        rows: Int,
        spacingX: Int = 0,
        spacingY: Int = 0,
        flipAlternateColumns: Bool = false,
        flipAlternateRows: Bool = false
    ) {
        self.columns = columns
        self.rows = rows
        self.spacingX = spacingX
        self.spacingY = spacingY
        self.flipAlternateColumns = flipAlternateColumns
        self.flipAlternateRows = flipAlternateRows
    }
}

enum PatternGenerator {
    /// Bygger en sammensatt, symmetrisk blokk fra ett motiv.
    static func symmetry(_ kind: SymmetryKind, motif: PatternMotif) -> PatternMotif {
        guard !motif.isEmpty else { return motif }

        switch kind {
        case .mirrorHorizontal:
            return mirroredHorizontally(motif)
        case .mirrorVertical:
            return mirroredVertically(motif)
        case .rotate4:
            return rotatedRosette(motif)
        }
    }

    /// Gjentar et motiv i et rutemønster av `columns` × `rows` fliser.
    static func tiled(_ options: TilingOptions, motif: PatternMotif) -> PatternMotif {
        guard !motif.isEmpty else { return motif }

        let columns = max(1, options.columns)
        let rows = max(1, options.rows)
        let spacingX = max(0, options.spacingX)
        let spacingY = max(0, options.spacingY)
        let stepX = motif.width + spacingX
        let stepY = motif.height + spacingY

        var cells: [GridCoordinate: UUID] = [:]
        cells.reserveCapacity(motif.cells.count * columns * rows)

        for row in 0..<rows {
            let flipY = options.flipAlternateRows && !row.isMultiple(of: 2)
            for column in 0..<columns {
                let flipX = options.flipAlternateColumns && !column.isMultiple(of: 2)
                let originX = column * stepX
                let originY = row * stepY

                for (coordinate, swatchID) in motif.cells {
                    let localX = flipX ? (motif.width - 1 - coordinate.x) : coordinate.x
                    let localY = flipY ? (motif.height - 1 - coordinate.y) : coordinate.y
                    cells[GridCoordinate(x: originX + localX, y: originY + localY)] = swatchID
                }
            }
        }

        return normalized(cells)
    }

    // MARK: - Symmetri-byggesteiner

    private static func mirroredHorizontally(_ motif: PatternMotif) -> PatternMotif {
        let mirrorWidth = motif.width
        var cells = motif.cells
        for (coordinate, swatchID) in motif.cells {
            let mirrored = GridCoordinate(x: 2 * mirrorWidth - 1 - coordinate.x, y: coordinate.y)
            cells[mirrored] = swatchID
        }
        return PatternMotif(cells: cells, width: motif.width * 2, height: motif.height)
    }

    private static func mirroredVertically(_ motif: PatternMotif) -> PatternMotif {
        let mirrorHeight = motif.height
        var cells = motif.cells
        for (coordinate, swatchID) in motif.cells {
            let mirrored = GridCoordinate(x: coordinate.x, y: 2 * mirrorHeight - 1 - coordinate.y)
            cells[mirrored] = swatchID
        }
        return PatternMotif(cells: cells, width: motif.width, height: motif.height * 2)
    }

    /// Plasserer fire 90°-roterte kopier rundt et felles senter i et kvadratisk
    /// felt med side `width + height`. Kopiene legger seg i hvert sitt
    /// "vindmølle"-felt uten å overlappe.
    private static func rotatedRosette(_ motif: PatternMotif) -> PatternMotif {
        let side = motif.width + motif.height
        var cells: [GridCoordinate: UUID] = [:]
        cells.reserveCapacity(motif.cells.count * 4)

        for (coordinate, swatchID) in motif.cells {
            var point = coordinate
            for _ in 0..<4 {
                cells[point] = swatchID
                // 90° med klokken i et `side`×`side`-felt: (x, y) -> (side-1-y, x).
                point = GridCoordinate(x: side - 1 - point.y, y: point.x)
            }
        }

        return PatternMotif(cells: cells, width: side, height: side)
    }

    // MARK: - Hjelpere

    /// Forskyver celler så bounding-boksen starter i (0,0) og regner ut størrelse.
    static func normalized(_ cells: [GridCoordinate: UUID]) -> PatternMotif {
        guard let bounds = cells.keys.bounds else {
            return PatternMotif(cells: [:], width: 0, height: 0)
        }

        var normalizedCells: [GridCoordinate: UUID] = [:]
        normalizedCells.reserveCapacity(cells.count)
        for (coordinate, swatchID) in cells {
            let shifted = GridCoordinate(x: coordinate.x - bounds.minX, y: coordinate.y - bounds.minY)
            normalizedCells[shifted] = swatchID
        }

        return PatternMotif(cells: normalizedCells, width: bounds.width, height: bounds.height)
    }
}

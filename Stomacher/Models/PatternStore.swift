import Foundation
import SwiftUI

enum CanvasTool: String, CaseIterable, Identifiable {
    case hand
    case paint
    case erase
    case outline
    case select
    case pipette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: "Flytt"
        case .paint: "Tegn"
        case .erase: "Visk"
        case .outline: "Ytterkant"
        case .select: "Marker"
        case .pipette: "Pipette"
        }
    }

    var systemImage: String {
        switch self {
        case .hand: "hand.raised"
        case .paint: "paintbrush.pointed"
        case .erase: "eraser"
        case .outline: "lasso"
        case .select: "selection.pin.in.out"
        case .pipette: "eyedropper"
        }
    }
}

enum SelectionMode: String, CaseIterable, Identifiable {
    case rectangle
    case singleCells

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: "Rektangel"
        case .singleCells: "Enkeltruter"
        }
    }
}

@MainActor
final class PatternStore: ObservableObject {
    @Published var document: PatternDocument
    @Published var selectedSwatchID: UUID
    @Published var tool: CanvasTool = .paint
    @Published var selectionMode: SelectionMode = .rectangle
    @Published var selection = Set<GridCoordinate>()
    @Published var clipboard: [GridCoordinate: UUID] = [:]
    @Published var zoom: CGFloat = 1
    @Published var usesApplePencilForEditing = false
    @Published var lastTouchedCoordinate: GridCoordinate?
    @Published var statusMessage = "Klar"
    @Published var hasUnsavedChanges = false
    @Published var autosaveEnabled = false
    @Published private(set) var currentDocumentURL: URL?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var selectionAnchor: GridCoordinate?
    private var interactionPreviousCoordinate: GridCoordinate?

    init(document: PatternDocument = PatternDocument()) {
        self.document = document
        self.selectedSwatchID = document.palette.first?.id ?? UUID()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var selectedSwatch: PaletteSwatch? {
        document.palette.first { $0.id == selectedSwatchID }
    }

    var documentURL: URL {
        documentsDirectory.appendingPathComponent("bringeduk-\(document.id.uuidString).stom")
    }

    func updateTitle(_ title: String) {
        document.title = title
        touch()
    }

    func updateTechnique(_ technique: PatternTechnique) {
        document.technique = technique
        touch()
    }

    func togglePaintAndEraseFromPencilDoubleTap() {
        if tool == .erase {
            tool = .paint
            statusMessage = "Tegn"
        } else {
            tool = .erase
            statusMessage = "Visk"
        }
    }

    func beginInteraction(at coordinate: GridCoordinate) {
        guard contains(coordinate) else { return }
        selectionAnchor = coordinate
        interactionPreviousCoordinate = coordinate

        if tool == .select, selectionMode == .rectangle {
            selectRectangle(from: coordinate, to: coordinate)
        } else {
            handleTapOrDrag(at: coordinate)
        }
    }

    func updateInteraction(at coordinate: GridCoordinate) {
        guard contains(coordinate) else { return }

        if tool == .outline, let previous = interactionPreviousCoordinate {
            addOutlineLine(from: previous, to: coordinate)
            interactionPreviousCoordinate = coordinate
        } else if tool == .select, selectionMode == .rectangle, let selectionAnchor {
            selectRectangle(from: selectionAnchor, to: coordinate)
        } else {
            handleTapOrDrag(at: coordinate)
        }
    }

    func endInteraction() {
        selectionAnchor = nil
        interactionPreviousCoordinate = nil
    }

    func handleTapOrDrag(at coordinate: GridCoordinate) {
        guard contains(coordinate) else { return }
        lastTouchedCoordinate = coordinate

        switch tool {
        case .hand:
            statusMessage = "Flytt mønsteret"
        case .paint:
            guard document.isWithinPatternArea(coordinate) else {
                statusMessage = "Utenfor ytterkant"
                return
            }
            document.cells[coordinate] = selectedSwatchID
            selection.removeAll()
            touch()
        case .erase:
            let removedOutline = document.outlineCells.remove(coordinate) != nil
            document.cells.removeValue(forKey: coordinate)
            selection.remove(coordinate)
            touch()
            statusMessage = removedOutline ? "Fjernet ytterkant" : "Visket"
        case .outline:
            document.outlineCells.insert(coordinate)
            selection.removeAll()
            touch()
            statusMessage = document.activePatternArea() == nil ? "Tegn en lukket ytterkant" : "Ytterkant"
        case .select:
            guard document.isWithinPatternArea(coordinate) else {
                statusMessage = "Utenfor ytterkant"
                return
            }
            selection.insert(coordinate)
            statusMessage = "\(selection.count) markert"
        case .pipette:
            if let swatchID = document.cells[coordinate] {
                selectedSwatchID = swatchID
                tool = .paint
            }
        }
    }

    func clearSelection() {
        selection.removeAll()
    }

    func copySelection() {
        guard let bounds = selection.bounds else { return }
        clipboard = selection.reduce(into: [:]) { partialResult, coordinate in
            guard let swatchID = document.cells[coordinate] else { return }
            partialResult[GridCoordinate(x: coordinate.x - bounds.minX, y: coordinate.y - bounds.minY)] = swatchID
        }
        statusMessage = "Kopierte \(clipboard.count) felt"
    }

    func pasteClipboard() {
        guard !clipboard.isEmpty else { return }
        let origin = lastTouchedCoordinate ?? GridCoordinate(x: document.width / 2, y: document.height / 2)

        for (offset, swatchID) in clipboard {
            let target = GridCoordinate(x: origin.x + offset.x, y: origin.y + offset.y)
            guard contains(target) else { continue }
            guard document.isWithinPatternArea(target) else { continue }
            document.cells[target] = swatchID
        }

        selection = Set(clipboard.keys.map { GridCoordinate(x: origin.x + $0.x, y: origin.y + $0.y) })
        touch()
        statusMessage = "Limte inn \(clipboard.count) felt"
    }

    func mirrorSelectionHorizontally() {
        transformSelection { coordinate, bounds in
            GridCoordinate(x: bounds.maxX - (coordinate.x - bounds.minX), y: coordinate.y)
        }
    }

    func mirrorSelectionVertically() {
        transformSelection { coordinate, bounds in
            GridCoordinate(x: coordinate.x, y: bounds.maxY - (coordinate.y - bounds.minY))
        }
    }

    func rotateSelectionClockwise() {
        guard let bounds = selection.bounds else { return }
        let snapshot = selectedPaintedCells()
        clearCells(in: selection)

        var newSelection = Set<GridCoordinate>()
        for (coordinate, swatchID) in snapshot {
            let dx = coordinate.x - bounds.minX
            let dy = coordinate.y - bounds.minY
            let target = GridCoordinate(x: bounds.minX + bounds.height - 1 - dy, y: bounds.minY + dx)
            guard contains(target) else { continue }
            document.cells[target] = swatchID
            newSelection.insert(target)
        }

        selection = newSelection
        touch()
    }

    func completeQuarterAsSquare() {
        guard let bounds = selection.bounds else { return }
        let snapshot = selectedPaintedCells()
        var newSelection = selection

        for (coordinate, swatchID) in snapshot {
            let dx = coordinate.x - bounds.minX
            let dy = coordinate.y - bounds.minY
            let targets = [
                GridCoordinate(x: bounds.minX + dx, y: bounds.minY + dy),
                GridCoordinate(x: bounds.minX + (bounds.width * 2 - 1 - dx), y: bounds.minY + dy),
                GridCoordinate(x: bounds.minX + dx, y: bounds.minY + (bounds.height * 2 - 1 - dy)),
                GridCoordinate(x: bounds.minX + (bounds.width * 2 - 1 - dx), y: bounds.minY + (bounds.height * 2 - 1 - dy))
            ]

            for target in targets where contains(target) {
                document.cells[target] = swatchID
                newSelection.insert(target)
            }
        }

        selection = newSelection
        touch()
        statusMessage = "Bygget kvadrat fra markert kvart"
    }

    func replaceColor(from source: UUID, to target: UUID) {
        guard source != target else { return }
        for (coordinate, swatchID) in document.cells where swatchID == source {
            document.cells[coordinate] = target
        }
        touch()
        statusMessage = "Byttet farge"
    }

    func croppedPaintedCellCount(width: Int, height: Int) -> Int {
        document.cells.keys.filter { coordinate in
            coordinate.x < 0 || coordinate.x >= width || coordinate.y < 0 || coordinate.y >= height
        }.count
    }

    func resize(width: Int, height: Int) {
        document.width = width
        document.height = height
        document.cells = document.cells.filter { coordinate, _ in
            coordinate.x >= 0 && coordinate.x < width && coordinate.y >= 0 && coordinate.y < height
        }
        document.outlineCells = document.outlineCells.filter { coordinate in
            coordinate.x >= 0 && coordinate.x < width && coordinate.y >= 0 && coordinate.y < height
        }
        selection = selection.filter { coordinate in
            coordinate.x >= 0 && coordinate.x < width && coordinate.y >= 0 && coordinate.y < height
        }
        touch()
        statusMessage = "Endret arbeidsflate"
    }

    var canAutosave: Bool {
        currentDocumentURL != nil
    }

    func save() throws {
        if let currentDocumentURL {
            try save(to: currentDocumentURL)
        } else {
            try save(to: documentURL)
        }
    }

    func save(to url: URL) throws {
        try writeDocument(to: url)
        markSaved(to: url)
    }

    func autosaveIfNeeded() throws {
        guard autosaveEnabled, hasUnsavedChanges, let currentDocumentURL else { return }
        try writeDocument(to: currentDocumentURL)
        markSaved(to: currentDocumentURL, message: "Autosave lagret")
    }

    func load(url: URL) throws {
        let data = try Data(contentsOf: url)
        document = try decoder.decode(PatternDocument.self, from: data)
        selectedSwatchID = document.palette.first?.id ?? selectedSwatchID
        selection.removeAll()
        clipboard.removeAll()
        currentDocumentURL = url
        statusMessage = "Åpnet \(document.title)"
        hasUnsavedChanges = false
    }

    func newDocument() {
        document = PatternDocument()
        selectedSwatchID = document.palette.first?.id ?? selectedSwatchID
        selection.removeAll()
        clipboard.removeAll()
        currentDocumentURL = nil
        autosaveEnabled = false
        statusMessage = "Ny arbeidsflate"
        hasUnsavedChanges = false
    }

    func clearOutline() {
        document.outlineCells.removeAll()
        touch()
        statusMessage = "Fjernet ytterkant"
    }

    func markSaved(to url: URL? = nil, message: String = "Lagret") {
        if let url {
            currentDocumentURL = url
        }
        statusMessage = message
        hasUnsavedChanges = false
    }

    private func transformSelection(_ transform: (GridCoordinate, GridBounds) -> GridCoordinate) {
        guard let bounds = selection.bounds else { return }
        let snapshot = selectedPaintedCells()
        clearCells(in: selection)

        var newSelection = Set<GridCoordinate>()
        for (coordinate, swatchID) in snapshot {
            let target = transform(coordinate, bounds)
            guard contains(target) else { continue }
            document.cells[target] = swatchID
            newSelection.insert(target)
        }

        selection = newSelection
        touch()
    }

    private func selectedPaintedCells() -> [GridCoordinate: UUID] {
        selection.reduce(into: [:]) { partialResult, coordinate in
            if let swatchID = document.cells[coordinate] {
                partialResult[coordinate] = swatchID
            }
        }
    }

    private func clearCells(in coordinates: Set<GridCoordinate>) {
        for coordinate in coordinates {
            document.cells.removeValue(forKey: coordinate)
        }
    }

    private func selectRectangle(from start: GridCoordinate, to end: GridCoordinate) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let minY = min(start.y, end.y)
        let maxY = max(start.y, end.y)

        var coordinates = Set<GridCoordinate>()
        for y in minY...maxY {
            for x in minX...maxX {
                let coordinate = GridCoordinate(x: x, y: y)
                guard contains(coordinate) else { continue }
                guard document.isWithinPatternArea(coordinate) else { continue }
                coordinates.insert(coordinate)
            }
        }

        selection = coordinates
        lastTouchedCoordinate = end
        statusMessage = "\(selection.count) markert"
    }

    private func contains(_ coordinate: GridCoordinate) -> Bool {
        coordinate.x >= 0 && coordinate.x < document.width && coordinate.y >= 0 && coordinate.y < document.height
    }

    private func touch() {
        document.updatedAt = Date()
        hasUnsavedChanges = true
    }

    private func addOutlineLine(from start: GridCoordinate, to end: GridCoordinate) {
        for coordinate in coordinatesOnLine(from: start, to: end) where contains(coordinate) {
            document.outlineCells.insert(coordinate)
        }

        selection.removeAll()
        touch()
        statusMessage = document.activePatternArea() == nil ? "Tegn en lukket ytterkant" : "Ytterkant"
    }

    private func coordinatesOnLine(from start: GridCoordinate, to end: GridCoordinate) -> [GridCoordinate] {
        var coordinates: [GridCoordinate] = []
        var x = start.x
        var y = start.y
        let dx = abs(end.x - start.x)
        let dy = -abs(end.y - start.y)
        let stepX = start.x < end.x ? 1 : -1
        let stepY = start.y < end.y ? 1 : -1
        var error = dx + dy

        while true {
            coordinates.append(GridCoordinate(x: x, y: y))
            guard x != end.x || y != end.y else { break }
            let doubledError = 2 * error
            if doubledError >= dy {
                error += dy
                x += stepX
            }
            if doubledError <= dx {
                error += dx
                y += stepY
            }
        }

        return coordinates
    }

    private func writeDocument(to url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try encoder.encode(document)
        try data.write(to: url, options: .atomic)
    }

    private var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

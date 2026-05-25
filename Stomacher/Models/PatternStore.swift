import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "no.abrahamsen.stomacher", category: "FileSystem")

enum CanvasTool: String, CaseIterable, Identifiable {
    case hand
    case paint
    case fill
    case erase
    case outline
    case select
    case pipette
    case replaceColor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hand: "Flytt"
        case .paint: "Tegn"
        case .fill: "Fyll inn"
        case .erase: "Visk"
        case .outline: "Ytterkant"
        case .select: "Marker"
        case .pipette: "Pipette"
        case .replaceColor: "Bytt farge"
        }
    }

    var systemImage: String {
        switch self {
        case .hand: "hand.raised"
        case .paint: "paintbrush.pointed"
        case .fill: "square.fill"
        case .erase: "eraser"
        case .outline: "lasso"
        case .select: "selection.pin.in.out"
        case .pipette: "eyedropper"
        case .replaceColor: "arrow.triangle.2.circlepath"
        }
    }
}

struct PendingFillConfirmation: Identifiable {
    let id = UUID()
    var targets: [GridCoordinate]
    var swatchID: UUID

    var count: Int { targets.count }
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

enum MoveMode: String, CaseIterable, Identifiable {
    case sheet
    case pattern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sheet: "Ark"
        case .pattern: "Mønster"
        }
    }
}

@MainActor
final class PatternStore: ObservableObject {
    @Published var document: PatternDocument
    @Published var selectedSwatchID: UUID
    @Published var tool: CanvasTool = .paint
    @Published var moveMode: MoveMode = .sheet
    @Published var selectionMode: SelectionMode = .rectangle
    @Published var selection = Set<GridCoordinate>()
    @Published var clipboard: [GridCoordinate: UUID] = [:]
    @Published var zoom: CGFloat = 1
    @Published private(set) var patternMovePreviewOffset = GridCoordinate(x: 0, y: 0)
    @Published var usesApplePencilForEditing = false {
        didSet {
            UserDefaults.standard.set(usesApplePencilForEditing, forKey: Self.applePencilEditingKey)
        }
    }
    @Published var isAutolockEnabled = true {
        didSet {
            UserDefaults.standard.set(isAutolockEnabled, forKey: Self.autolockEnabledKey)
        }
    }
    @Published var lastTouchedCoordinate: GridCoordinate?
    @Published var statusMessage = "Klar"
    @Published var hasUnsavedChanges = false
    @Published var pendingFillConfirmation: PendingFillConfirmation?
    @Published private(set) var customPalettes: [PatternPalette] = []
    @Published private(set) var currentDocumentURL: URL?

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let applePencilEditingKey = "no.abrahamsen.stomacher.usesApplePencilForEditing"
    private static let autolockEnabledKey = "no.abrahamsen.stomacher.isAutolockEnabled"
    private let customPalettesKey = "no.abrahamsen.stomacher.customPalettes"
    private var autosaveTask: Task<Void, Never>?
    private var selectionAnchor: GridCoordinate?
    private var interactionPreviousCoordinate: GridCoordinate?
    private var patternMoveSnapshot: PatternMoveSnapshot?
    private var patternMoveAppliedOffset = GridCoordinate(x: 0, y: 0)

    init(document: PatternDocument = PatternDocument()) {
        self.document = document
        self.selectedSwatchID = document.palette.first?.id ?? UUID()
        self.usesApplePencilForEditing = UserDefaults.standard.bool(forKey: Self.applePencilEditingKey)
        self.isAutolockEnabled = UserDefaults.standard.object(forKey: Self.autolockEnabledKey) as? Bool ?? true
        self.customPalettes = Self.loadCustomPalettes(key: customPalettesKey)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        normalizeCurrentPalette()
    }

    var selectedSwatch: PaletteSwatch? {
        document.palette.first { $0.id == selectedSwatchID }
    }

    var palettes: [PatternPalette] {
        let storedPalettes = PatternPalette.builtInPalettes + customPalettes
        guard !storedPalettes.contains(where: { $0.id == document.paletteID }) else {
            return storedPalettes
        }

        return storedPalettes + [selectedPalette]
    }

    var selectedPalette: PatternPalette {
        PatternPalette(
            id: document.paletteID,
            name: document.paletteName,
            swatches: document.palette
        )
    }

    var canDeleteSelectedPalette: Bool {
        customPalettes.contains { $0.id == document.paletteID }
    }

    var documentURL: URL {
        stomacherDocumentsDirectory.appendingPathComponent("bringeduk-\(document.id.uuidString).stom")
    }

    var sewingCurrentCoordinate: GridCoordinate? {
        guard document.isProtected else { return nil }
        return document.sewingProgress?.current
    }

    var sewingPassedCells: Set<GridCoordinate> {
        guard document.isProtected, let progress = document.sewingProgress else { return [] }
        let traversal = document.sewingTraversal(from: progress.startCorner)
        guard let currentIndex = traversal.firstIndex(of: progress.current), currentIndex > 0 else { return [] }
        return Set(traversal[..<currentIndex])
    }

    var canAdvanceSewingCell: Bool {
        nextSewingCell() != nil
    }

    var canAdvanceSewingLine: Bool {
        nextSewingLineStart() != nil
    }

    func updateTitle(_ title: String) {
        guard canEditPattern else { return }
        document.title = title
        touch()
    }

    func updateDescription(_ description: String) {
        guard canEditPattern else { return }
        document.patternDescription = description
        touch()
        statusMessage = "Oppdatert beskrivelse"
    }

    func updateTechnique(_ technique: PatternTechnique) {
        guard canEditPattern else { return }
        document.technique = technique
        touch()
    }

    func updateGridBlockSize(_ gridBlockSize: Int) {
        guard canEditPattern else { return }
        document.gridBlockSize = PatternDocument.normalizedGridBlockSize(gridBlockSize)
        touch()
    }

    func updateHideUnusedArea(_ hideUnusedArea: Bool) {
        guard canEditPattern else { return }
        document.hideUnusedArea = hideUnusedArea
        touch()
    }

    func updateProtected(_ isProtected: Bool) {
        guard document.isProtected != isProtected else { return }
        document.isProtected = isProtected
        if isProtected {
            tool = .hand
            moveMode = .sheet
            selection.removeAll()
            statusMessage = "Mønsteret er beskyttet"
        } else {
            statusMessage = "Beskyttelse er slått av"
        }
        touch()
    }

    func startSewing(from startCorner: SewingStartCorner) {
        guard document.isProtected else { return }
        guard let current = document.sewingTraversal(from: startCorner).first else {
            statusMessage = "Ingen ruter å sy"
            return
        }

        document.sewingProgress = SewingProgress(startCorner: startCorner, current: current)
        tool = .hand
        moveMode = .sheet
        selection.removeAll()
        zoom = 2.4
        touch()
        statusMessage = "Sy: \(current.x), \(current.y)"
    }

    func resumeSewing() {
        guard document.isProtected, document.sewingProgress != nil else { return }
        tool = .hand
        moveMode = .sheet
        zoom = 2.4
        statusMessage = "Sy videre"
    }

    func advanceSewingCell() {
        guard let next = nextSewingCell() else {
            statusMessage = "Siste rute"
            return
        }

        document.sewingProgress?.current = next
        touch()
        statusMessage = "Sy: \(next.x), \(next.y)"
    }

    func advanceSewingLine() {
        guard let next = nextSewingLineStart() else {
            statusMessage = "Siste linje"
            return
        }

        document.sewingProgress?.current = next
        touch()
        statusMessage = "Sy: \(next.x), \(next.y)"
    }

    func jumpSewing(to coordinate: GridCoordinate) {
        guard document.isProtected, let progress = document.sewingProgress else { return }
        guard document.cells[coordinate] != nil else { return }
        let traversal = document.sewingTraversal(from: progress.startCorner)
        guard traversal.contains(coordinate) else { return }

        document.sewingProgress?.current = coordinate
        touch()
        statusMessage = "Sy: \(coordinate.x), \(coordinate.y)"
    }

    func cancelSewing() {
        guard document.sewingProgress != nil else { return }
        document.sewingProgress = nil
        touch()
        statusMessage = "Sy-fremdrift avbrutt"
    }

    func togglePaintAndEraseFromPencilDoubleTap() {
        guard canEditPattern else { return }
        if tool == .erase {
            tool = .paint
            statusMessage = "Tegn"
        } else {
            tool = .erase
            statusMessage = "Visk"
        }
    }

    func beginInteraction(at coordinate: GridCoordinate) {
        if document.isProtected {
            jumpSewing(to: coordinate)
            return
        }

        guard canEditPattern else { return }
        guard contains(coordinate) else { return }

        if tool == .fill {
            requestFill(at: coordinate)
            return
        }

        selectionAnchor = coordinate
        interactionPreviousCoordinate = coordinate

        if tool == .hand, moveMode == .pattern {
            beginPatternMove(at: coordinate)
        } else if tool == .select, selectionMode == .rectangle {
            selectRectangle(from: coordinate, to: coordinate)
        } else {
            handleTapOrDrag(at: coordinate)
        }
    }

    func updateInteraction(at coordinate: GridCoordinate) {
        if document.isProtected {
            jumpSewing(to: coordinate)
            return
        }

        guard canEditPattern else { return }
        if tool == .hand, moveMode == .pattern {
            updatePatternMove(to: coordinate)
            return
        }

        guard contains(coordinate) else { return }
        guard tool != .fill else { return }

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
        commitPatternMove()
        selectionAnchor = nil
        interactionPreviousCoordinate = nil
        patternMoveSnapshot = nil
        patternMovePreviewOffset = GridCoordinate(x: 0, y: 0)
        patternMoveAppliedOffset = GridCoordinate(x: 0, y: 0)
    }

    func handleTapOrDrag(at coordinate: GridCoordinate) {
        guard canEditPattern else {
            statusMessage = "Mønsteret er beskyttet"
            return
        }
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
        case .fill:
            statusMessage = "Trykk i et område for å fylle"
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
        case .replaceColor:
            statusMessage = "Velg farger i verktøypanelet"
        }
    }

    func clearSelection() {
        selection.removeAll()
    }

    func copySelection() {
        clipboard = clipboardSnapshotForSelection()
        statusMessage = "Kopierte \(clipboard.count) felt"
    }

    func cutSelection() {
        guard canEditPattern else { return }
        let snapshot = clipboardSnapshotForSelection()
        guard !snapshot.isEmpty else { return }

        clipboard = snapshot
        clearCells(in: selection)
        touch()
        statusMessage = "Klippet ut \(clipboard.count) felt"
    }

    func pasteClipboard() {
        guard canEditPattern else { return }
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
        guard canEditPattern else { return }
        transformSelection { coordinate, bounds in
            GridCoordinate(x: bounds.maxX - (coordinate.x - bounds.minX), y: coordinate.y)
        }
    }

    func mirrorSelectionVertically() {
        guard canEditPattern else { return }
        transformSelection { coordinate, bounds in
            GridCoordinate(x: coordinate.x, y: bounds.maxY - (coordinate.y - bounds.minY))
        }
    }

    func rotateSelectionClockwise() {
        guard canEditPattern else { return }
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
        guard canEditPattern else { return }
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
        guard canEditPattern else { return }
        guard source != target else { return }
        for (coordinate, swatchID) in document.cells where swatchID == source {
            document.cells[coordinate] = target
        }
        touch()
        statusMessage = "Byttet farge"
    }

    func confirmPendingFill() {
        guard canEditPattern else { return }
        guard let pendingFillConfirmation else { return }
        self.pendingFillConfirmation = nil
        applyFill(targets: pendingFillConfirmation.targets, swatchID: pendingFillConfirmation.swatchID)
    }

    func cancelPendingFill() {
        pendingFillConfirmation = nil
    }

    func applyPalette(id: UUID) {
        guard canEditPattern else { return }
        guard let palette = palettes.first(where: { $0.id == id }) else { return }
        document.paletteID = palette.id
        document.paletteName = palette.name
        document.palette = PatternPalette.normalizedSwatches(palette.swatches)
        selectedSwatchID = document.palette.first(where: { $0.id == selectedSwatchID })?.id ?? document.palette.first?.id ?? selectedSwatchID
        touch()
        statusMessage = "Palett: \(palette.name)"
    }

    func saveCustomPalette(name: String, swatches: [PaletteSwatch], replacing paletteID: UUID?) {
        guard canEditPattern else { return }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let paletteName = cleanedName.isEmpty ? "Egendefinert palett" : cleanedName
        let normalizedSwatches = PatternPalette.normalizedSwatches(swatches)

        let palette: PatternPalette
        if let paletteID, let index = customPalettes.firstIndex(where: { $0.id == paletteID }) {
            palette = PatternPalette(id: paletteID, name: paletteName, swatches: normalizedSwatches)
            customPalettes[index] = palette
        } else {
            palette = PatternPalette(id: UUID(), name: paletteName, swatches: normalizedSwatches)
            customPalettes.append(palette)
        }

        persistCustomPalettes()
        applyPalette(id: palette.id)
        statusMessage = "Lagret palett: \(palette.name)"
    }

    func deleteCustomPalette(id: UUID) {
        guard canEditPattern else { return }
        guard let index = customPalettes.firstIndex(where: { $0.id == id }) else { return }
        let deletedName = customPalettes[index].name
        customPalettes.remove(at: index)
        persistCustomPalettes()

        if document.paletteID == id {
            applyPalette(id: PatternPalette.standardID)
        }

        statusMessage = "Slettet palett: \(deletedName)"
    }

    func croppedPaintedCellCount(width: Int, height: Int) -> Int {
        document.cells.keys.filter { coordinate in
            coordinate.x < 0 || coordinate.x >= width || coordinate.y < 0 || coordinate.y >= height
        }.count
    }

    func resize(width: Int, height: Int) {
        guard canEditPattern else { return }
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

    var containerDocumentsURL: URL? {
        try? defaultExportDirectory().url
    }

    func save() throws {
        if let currentDocumentURL {
            try save(to: currentDocumentURL)
        } else {
            try saveToDefaultLocation()
        }
    }

    func save(to url: URL) throws {
        logger.info("Saving to: \(url.path, privacy: .public)")
        try writeDocument(to: url)
        markSaved(to: url)
    }

    func saveToDefaultLocation(filename: String? = nil) throws {
        let directory = try defaultExportDirectory().url
        let requestedFilename = filename ?? document.title.stomFileName
        let url = uniqueFileURL(in: directory, filename: requestedFilename)
        try save(to: url)
    }

    func prepareExportCopy(filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StomacherExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(filename)
        try writeDocument(to: url)
        return url
    }

    func writeAutosaveCopyIfNeeded() throws {
        guard hasUnsavedChanges else { return }

        let directory = try defaultExportDirectory().url
        let url = directory.appendingPathComponent("autosave.stom")
        logger.info("Writing autosave copy to: \(url.path, privacy: .public)")
        try writeDocument(to: url)
        statusMessage = "Autosave lagret"
    }

    func startAutosave() {
        guard autosaveTask == nil else { return }

        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.runAutosave()
            }
        }
    }

    func stopAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

    private func runAutosave() {
        do {
            try writeAutosaveCopyIfNeeded()
        } catch {
            statusMessage = "Autosave feilet: \(error.localizedDescription)"
        }
    }

    func load(url: URL) throws {
        logger.info("Loading from: \(url.path, privacy: .public)")
        let data = try Data(contentsOf: url)
        document = try decoder.decode(PatternDocument.self, from: data)
        normalizeCurrentPalette()
        selectedSwatchID = document.palette.first?.id ?? selectedSwatchID
        selection.removeAll()
        clipboard.removeAll()
        currentDocumentURL = url
        statusMessage = "Åpnet \(document.title)"
        hasUnsavedChanges = false
    }

    func newDocument() {
        document = PatternDocument()
        normalizeCurrentPalette()
        selectedSwatchID = document.palette.first?.id ?? selectedSwatchID
        selection.removeAll()
        clipboard.removeAll()
        currentDocumentURL = nil
        statusMessage = "Ny arbeidsflate"
        hasUnsavedChanges = false
    }

    func clearOutline() {
        guard canEditPattern else { return }
        document.outlineCells.removeAll()
        touch()
        statusMessage = "Fjernet ytterkant"
    }

    func markSaved(to url: URL? = nil, message: String? = nil) {
        if let url {
            currentDocumentURL = url
            statusMessage = message ?? Self.savedMessage(for: url)
        } else {
            statusMessage = message ?? "Lagret"
        }
        hasUnsavedChanges = false
    }

    private static func savedMessage(for url: URL) -> String {
        let path = url.path
        if path.contains("/Mobile Documents/com~apple~CloudDocs/") {
            return "Lagret til iCloud Drive"
        }
        if path.contains("/Mobile Documents/") {
            return "Lagret til app-container (kun synlig med appen installert)"
        }
        return "Lagret lokalt"
    }

    private func transformSelection(_ transform: (GridCoordinate, GridBounds) -> GridCoordinate) {
        guard canEditPattern else { return }
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

    private func beginPatternMove(at coordinate: GridCoordinate) {
        guard canEditPattern else { return }
        guard let bounds = patternContentBounds else {
            statusMessage = "Ingen ruter å flytte"
            return
        }

        patternMoveSnapshot = PatternMoveSnapshot(
            start: coordinate,
            bounds: bounds,
            cells: document.cells,
            outlineCells: document.outlineCells,
            selection: selection
        )
        patternMoveAppliedOffset = GridCoordinate(x: 0, y: 0)
        patternMovePreviewOffset = GridCoordinate(x: 0, y: 0)
        statusMessage = "Flytter mønster"
    }

    private func updatePatternMove(to coordinate: GridCoordinate) {
        guard canEditPattern else { return }
        guard let snapshot = patternMoveSnapshot else { return }

        let requestedOffset = GridCoordinate(
            x: coordinate.x - snapshot.start.x,
            y: coordinate.y - snapshot.start.y
        )
        let offset = clampedMoveOffset(requestedOffset, for: snapshot.bounds)
        guard offset != patternMoveAppliedOffset else {
            if offset != requestedOffset {
                statusMessage = "Kanten er nådd"
            }
            return
        }

        patternMoveAppliedOffset = offset
        patternMovePreviewOffset = offset
        statusMessage = "Flyttet mønster \(offset.x), \(offset.y)"
    }

    private func commitPatternMove() {
        guard canEditPattern else { return }
        guard let snapshot = patternMoveSnapshot else { return }
        let offset = patternMovePreviewOffset
        guard offset != GridCoordinate(x: 0, y: 0) else { return }

        document.cells = snapshot.cells.reduce(into: [:]) { movedCells, entry in
            movedCells[entry.key.offsetBy(x: offset.x, y: offset.y)] = entry.value
        }
        document.outlineCells = Set(snapshot.outlineCells.map { $0.offsetBy(x: offset.x, y: offset.y) })
        selection = Set(snapshot.selection.map { $0.offsetBy(x: offset.x, y: offset.y) }.filter(contains))
        touch()
    }

    private var patternContentBounds: GridBounds? {
        (Array(document.cells.keys) + Array(document.outlineCells)).bounds
    }

    private func clampedMoveOffset(_ offset: GridCoordinate, for bounds: GridBounds) -> GridCoordinate {
        let minX = -bounds.minX
        let maxX = document.width - 1 - bounds.maxX
        let minY = -bounds.minY
        let maxY = document.height - 1 - bounds.maxY

        return GridCoordinate(
            x: min(max(offset.x, minX), maxX),
            y: min(max(offset.y, minY), maxY)
        )
    }

    private func selectedPaintedCells() -> [GridCoordinate: UUID] {
        selection.reduce(into: [:]) { partialResult, coordinate in
            if let swatchID = document.cells[coordinate] {
                partialResult[coordinate] = swatchID
            }
        }
    }

    private var canEditPattern: Bool {
        !document.isProtected
    }

    private func nextSewingCell() -> GridCoordinate? {
        guard document.isProtected, let progress = document.sewingProgress else { return nil }
        let traversal = document.sewingTraversal(from: progress.startCorner)
        guard let currentIndex = traversal.firstIndex(of: progress.current) else {
            return traversal.first
        }
        let nextIndex = traversal.index(after: currentIndex)
        guard nextIndex < traversal.endIndex else { return nil }
        return traversal[nextIndex]
    }

    private func nextSewingLineStart() -> GridCoordinate? {
        guard document.isProtected, let progress = document.sewingProgress else { return nil }
        let traversal = document.sewingTraversal(from: progress.startCorner)
        guard let currentIndex = traversal.firstIndex(of: progress.current) else {
            return traversal.first
        }

        for coordinate in traversal[traversal.index(after: currentIndex)...] where coordinate.y != progress.current.y {
            return coordinate
        }

        return nil
    }

    private func clipboardSnapshotForSelection() -> [GridCoordinate: UUID] {
        guard let bounds = selection.bounds else { return [:] }

        return selection.reduce(into: [:]) { partialResult, coordinate in
            guard let swatchID = document.cells[coordinate] else { return }
            partialResult[GridCoordinate(x: coordinate.x - bounds.minX, y: coordinate.y - bounds.minY)] = swatchID
        }
    }

    private func clearCells(in coordinates: Set<GridCoordinate>) {
        for coordinate in coordinates {
            document.cells.removeValue(forKey: coordinate)
        }
    }

    private func requestFill(at coordinate: GridCoordinate) {
        lastTouchedCoordinate = coordinate
        let targets = fillTargets(from: coordinate).filter { document.cells[$0] != selectedSwatchID }
        guard !targets.isEmpty else {
            statusMessage = "Området har allerede valgt farge"
            return
        }

        if targets.count > 100 {
            pendingFillConfirmation = PendingFillConfirmation(targets: targets, swatchID: selectedSwatchID)
        } else {
            applyFill(targets: targets, swatchID: selectedSwatchID)
        }
    }

    private func applyFill(targets: [GridCoordinate], swatchID: UUID) {
        for coordinate in targets {
            document.cells[coordinate] = swatchID
        }

        selection.removeAll()
        touch()
        statusMessage = "Fylte \(targets.count) ruter"
    }

    private func fillTargets(from start: GridCoordinate) -> [GridCoordinate] {
        guard contains(start) else { return [] }

        let startSwatchID = document.cells[start]
        var visited = Set<GridCoordinate>()
        var targets: [GridCoordinate] = []
        var queue = [start]
        var queueIndex = 0

        func canFill(_ coordinate: GridCoordinate) -> Bool {
            guard contains(coordinate) else { return false }
            if let startSwatchID {
                return document.cells[coordinate] == startSwatchID
            }
            return document.cells[coordinate] == nil
        }

        while queueIndex < queue.count {
            let coordinate = queue[queueIndex]
            queueIndex += 1

            guard !visited.contains(coordinate), canFill(coordinate) else { continue }
            visited.insert(coordinate)
            targets.append(coordinate)
            guard !document.outlineCells.contains(coordinate) else { continue }

            queue.append(GridCoordinate(x: coordinate.x + 1, y: coordinate.y))
            queue.append(GridCoordinate(x: coordinate.x - 1, y: coordinate.y))
            queue.append(GridCoordinate(x: coordinate.x, y: coordinate.y + 1))
            queue.append(GridCoordinate(x: coordinate.x, y: coordinate.y - 1))
        }

        return targets
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

    private var stomacherDocumentsDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("Stomacher", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func defaultExportDirectory() throws -> PreparedDirectory {
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            logger.info("iCloud container URL: \(containerURL.path, privacy: .public)")
            let dir = try prepareDirectory(at: containerURL.appendingPathComponent("Documents", isDirectory: true))
            logger.info("Using iCloud Documents directory: \(dir.url.path, privacy: .public)")
            return dir
        }

        logger.warning("iCloud container not available — falling back to local Documents/Stomacher")
        return try prepareDirectory(at: documentsDirectory.appendingPathComponent("Stomacher", isDirectory: true))
    }

    private func prepareDirectory(at url: URL) throws -> PreparedDirectory {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists, isDirectory.boolValue {
            return PreparedDirectory(url: url, wasCreated: false)
        }

        if exists {
            throw CocoaError(.fileWriteFileExists)
        }

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return PreparedDirectory(url: url, wasCreated: true)
    }

    private func uniqueFileURL(in directory: URL, filename: String) -> URL {
        let baseURL = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            return baseURL
        }

        let fileExtension = baseURL.pathExtension
        let baseName = baseURL.deletingPathExtension().lastPathComponent

        for index in 2...999 {
            let candidateName = fileExtension.isEmpty
                ? "\(baseName) \(index)"
                : "\(baseName) \(index).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        return directory.appendingPathComponent("\(baseName) \(UUID().uuidString).\(fileExtension)")
    }

    private func normalizeCurrentPalette() {
        document.palette = PatternPalette.normalizedSwatches(document.palette)

        if document.paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.paletteName = PatternPalette.standardName
        }

        if !palettes.contains(where: { $0.id == document.paletteID }) && document.paletteID == PatternPalette.standardID {
            document.paletteName = PatternPalette.standardName
        }
    }

    private func persistCustomPalettes() {
        do {
            let data = try encoder.encode(customPalettes)
            UserDefaults.standard.set(data, forKey: customPalettesKey)
        } catch {
            statusMessage = "Kunne ikke lagre paletter: \(error.localizedDescription)"
        }
    }

    private static func loadCustomPalettes(key: String) -> [PatternPalette] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        guard let palettes = try? decoder.decode([PatternPalette].self, from: data) else { return [] }

        return palettes
            .filter { !$0.isBuiltIn }
            .map { PatternPalette(id: $0.id, name: $0.name, swatches: PatternPalette.normalizedSwatches($0.swatches)) }
    }
}

private struct PatternMoveSnapshot {
    var start: GridCoordinate
    var bounds: GridBounds
    var cells: [GridCoordinate: UUID]
    var outlineCells: Set<GridCoordinate>
    var selection: Set<GridCoordinate>
}

private struct PreparedDirectory {
    var url: URL
    var wasCreated: Bool
}

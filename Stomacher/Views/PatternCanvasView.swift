import SwiftUI
import UIKit

struct PatternCanvasView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var store: PatternStore
    @State private var pinchStartZoom: CGFloat?

    private var baseCellSize: CGFloat { 18 }
    private var cellSize: CGFloat { baseCellSize * store.zoom }
    private var canvasSize: CGSize {
        CGSize(width: CGFloat(store.document.width) * cellSize, height: CGFloat(store.document.height) * cellSize)
    }
    private var canvasBackground: Color {
        colorScheme == .dark ? Color(white: 0.68) : Color(uiColor: .systemBackground)
    }
    private var workspaceBackground: Color {
        colorScheme == .dark ? Color(white: 0.42) : Color(uiColor: .secondarySystemBackground)
    }
    private var minorGridColor: Color {
        colorScheme == .dark ? .black.opacity(0.16) : .secondary.opacity(0.18)
    }
    private var majorGridColor: Color {
        colorScheme == .dark ? .black.opacity(0.34) : .secondary.opacity(0.36)
    }
    private var supportsApplePencilEditing: Bool {
        EditingInputSupport.supportsApplePencilEditing
    }

    var body: some View {
        let patternArea = store.document.activePatternArea()
        let patternOffset = store.patternMovePreviewOffset
        let colorBySwatchID = Dictionary(uniqueKeysWithValues: store.document.palette.map { ($0.id, $0.color) })
        let sewingPassedCells = store.sewingPassedCells
        let sewingCurrentCoordinate = store.sewingCurrentCoordinate

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas(opaque: true) { context, size in
                    drawBackground(in: &context, size: size)
                    drawOutsidePatternArea(in: &context, patternArea: patternArea, offset: patternOffset)
                    drawCells(in: &context, patternArea: patternArea, offset: patternOffset, colorBySwatchID: colorBySwatchID)
                    drawSewingProgress(in: &context, passedCells: sewingPassedCells, offset: patternOffset)
                    drawGrid(in: &context)
                    drawHiddenUnusedArea(in: &context, patternArea: patternArea, offset: patternOffset)
                    drawOutline(in: &context, patternArea: patternArea, offset: patternOffset)
                    drawSelection(in: &context, offset: patternOffset)
                    drawSewingCurrent(in: &context, currentCoordinate: sewingCurrentCoordinate, offset: patternOffset)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(canvasBackground)

                DrawInputOverlay(
                    store: store,
                    cellSize: cellSize,
                    isEnabled: isDrawInputEnabled,
                    usesApplePencilOnly: usesPencilOnlyInput
                )
                .frame(width: canvasSize.width, height: canvasSize.height)

                SewingAutoScrollView(
                    coordinate: sewingCurrentCoordinate,
                    cellSize: cellSize,
                    contentPadding: 24
                )
                .frame(width: 1, height: 1)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(workspaceBackground)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let baseZoom = pinchStartZoom ?? store.zoom
                    pinchStartZoom = baseZoom
                    store.zoom = min(2.4, max(0.45, baseZoom * value))
                }
                .onEnded { _ in
                    pinchStartZoom = nil
                }
        )
    }

    private var isDrawInputEnabled: Bool {
        if store.document.isProtected {
            if EditingInputSupport.isRunningOnMac {
                return store.document.sewingProgress != nil
            }

            return supportsApplePencilEditing && store.usesApplePencilForEditing && store.document.sewingProgress != nil
        }

        return store.tool != .hand || store.moveMode == .pattern
    }

    private var usesPencilOnlyInput: Bool {
        supportsApplePencilEditing && (store.usesApplePencilForEditing || store.document.isProtected)
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(canvasBackground))
    }

    private func drawGrid(in context: inout GraphicsContext) {
        var minor = Path()
        for x in 0...store.document.width {
            let px = CGFloat(x) * cellSize
            minor.move(to: CGPoint(x: px, y: 0))
            minor.addLine(to: CGPoint(x: px, y: canvasSize.height))
        }
        for y in 0...store.document.height {
            let py = CGFloat(y) * cellSize
            minor.move(to: CGPoint(x: 0, y: py))
            minor.addLine(to: CGPoint(x: canvasSize.width, y: py))
        }
        context.stroke(minor, with: .color(minorGridColor), lineWidth: 0.6)

        var major = Path()
        for x in stride(from: 0, through: store.document.width, by: store.document.gridBlockSize) {
            let px = CGFloat(x) * cellSize
            major.move(to: CGPoint(x: px, y: 0))
            major.addLine(to: CGPoint(x: px, y: canvasSize.height))
        }
        for y in stride(from: 0, through: store.document.height, by: store.document.gridBlockSize) {
            let py = CGFloat(y) * cellSize
            major.move(to: CGPoint(x: 0, y: py))
            major.addLine(to: CGPoint(x: canvasSize.width, y: py))
        }
        context.stroke(major, with: .color(majorGridColor), lineWidth: 1)
    }

    private func drawCells(
        in context: inout GraphicsContext,
        patternArea: Set<GridCoordinate>?,
        offset: GridCoordinate,
        colorBySwatchID: [UUID: Color]
    ) {
        let beadStroke = Color.black.opacity(0.22)
        let beadHighlight = Color.white.opacity(0.28)
        let beadStrokeWidth = max(0.7, cellSize * 0.045)
        let beadHighlightWidth = max(0.8, cellSize * 0.075)
        let stitchLineWidth = max(1.5, cellSize * 0.2)
        let symbolTemplates = CellSymbolTemplates(cellSize: cellSize)
        var coordinatesBySwatchID: [UUID: [GridCoordinate]] = [:]

        let movingSelection = store.isMovingSelection
        let selectionOffset = store.selectionMovePreviewOffset

        for (coordinate, swatchID) in store.document.cells {
            let cellOffset = (movingSelection && store.selection.contains(coordinate)) ? selectionOffset : offset
            let displayCoordinate = coordinate.offsetBy(x: cellOffset.x, y: cellOffset.y)
            guard colorBySwatchID[swatchID] != nil else { continue }
            guard patternArea?.contains(coordinate) ?? true else { continue }
            coordinatesBySwatchID[swatchID, default: []].append(displayCoordinate)
        }

        var beadHighlightPath = Path()

        for swatch in store.document.palette {
            guard let coordinates = coordinatesBySwatchID[swatch.id], let color = colorBySwatchID[swatch.id] else { continue }
            var path = Path()

            for coordinate in coordinates {
                let transform = CGAffineTransform(
                    translationX: CGFloat(coordinate.x) * cellSize,
                    y: CGFloat(coordinate.y) * cellSize
                )

                switch store.document.technique {
                case .beads:
                    path.addPath(symbolTemplates.beadPath, transform: transform)
                    beadHighlightPath.addPath(symbolTemplates.beadHighlightPath, transform: transform)
                case .crossStitches:
                    path.addPath(symbolTemplates.crossStitchPath, transform: transform)
                case .satinStitch:
                    path.addPath(symbolTemplates.satinStitchPath, transform: transform)
                }
            }

            switch store.document.technique {
            case .beads:
                context.fill(path, with: .color(color))
                context.stroke(path, with: .color(beadStroke), lineWidth: beadStrokeWidth)
            case .crossStitches:
                context.stroke(path, with: .color(color), lineWidth: stitchLineWidth)
            case .satinStitch:
                context.fill(path, with: .color(color))
            }
        }

        if store.document.technique == .beads {
            context.stroke(beadHighlightPath, with: .color(beadHighlight), lineWidth: beadHighlightWidth)
        }
    }

    private func drawOutsidePatternArea(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?, offset: GridCoordinate) {
        guard let patternArea else { return }
        guard !store.document.hideUnusedArea else { return }
        let outsideColor: Color = colorScheme == .dark ? .black.opacity(0.16) : .black.opacity(0.07)
        var outsidePath = Path()

        for y in 0..<store.document.height {
            for x in 0..<store.document.width {
                let coordinate = GridCoordinate(x: x, y: y)
                let sourceCoordinate = coordinate.offsetBy(x: -offset.x, y: -offset.y)
                guard !patternArea.contains(sourceCoordinate) else { continue }
                outsidePath.addRect(rect(for: coordinate))
            }
        }

        context.fill(outsidePath, with: .color(outsideColor))
    }

    private func drawHiddenUnusedArea(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?, offset: GridCoordinate) {
        guard let patternArea, store.document.hideUnusedArea else { return }
        var hiddenPath = Path()

        for y in 0..<store.document.height {
            for x in 0..<store.document.width {
                let coordinate = GridCoordinate(x: x, y: y)
                let sourceCoordinate = coordinate.offsetBy(x: -offset.x, y: -offset.y)
                guard !patternArea.contains(sourceCoordinate) else { continue }
                hiddenPath.addRect(rect(for: coordinate))
            }
        }

        context.fill(hiddenPath, with: .color(workspaceBackground))
    }

    private func drawOutline(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?, offset: GridCoordinate) {
        guard store.document.hasCustomOutline else { return }

        if let patternArea {
            var outline = Path()

            for coordinate in store.document.outlineCells {
                let displayCoordinate = coordinate.offsetBy(x: offset.x, y: offset.y)
                addExteriorOutlineSegments(to: &outline, for: coordinate, displayCoordinate: displayCoordinate, patternArea: patternArea)
            }

            context.stroke(outline, with: .color(.red), lineWidth: max(2, cellSize * 0.16))
            return
        }

        for coordinate in store.document.outlineCells {
            let displayCoordinate = coordinate.offsetBy(x: offset.x, y: offset.y)
            let rect = rect(for: displayCoordinate).insetBy(dx: max(1, cellSize * 0.08), dy: max(1, cellSize * 0.08))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.orange), lineWidth: max(2, cellSize * 0.16))
        }
    }

    private func drawSewingProgress(
        in context: inout GraphicsContext,
        passedCells: Set<GridCoordinate>,
        offset: GridCoordinate
    ) {
        guard !passedCells.isEmpty else { return }

        var passedPath = Path()
        for coordinate in passedCells {
            let displayCoordinate = coordinate.offsetBy(x: offset.x, y: offset.y)
            passedPath.addRect(rect(for: displayCoordinate))
        }
        context.fill(passedPath, with: .color(Color.gray.opacity(0.72)))
    }

    private func drawSewingCurrent(in context: inout GraphicsContext, currentCoordinate: GridCoordinate?, offset: GridCoordinate) {
        guard let currentCoordinate else { return }
        let displayCoordinate = currentCoordinate.offsetBy(x: offset.x, y: offset.y)
        let rect = rect(for: displayCoordinate).insetBy(dx: 1, dy: 1)
        let lineWidth = max(1, min(2, cellSize * 0.055))
        context.stroke(Path(rect), with: .color(.yellow), lineWidth: lineWidth)
    }

    private func addExteriorOutlineSegments(to path: inout Path, for coordinate: GridCoordinate, displayCoordinate: GridCoordinate, patternArea: Set<GridCoordinate>) {
        let rect = rect(for: displayCoordinate)

        if !patternArea.contains(coordinate.offsetBy(x: 0, y: -1)) {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        if !patternArea.contains(coordinate.offsetBy(x: 1, y: 0)) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        if !patternArea.contains(coordinate.offsetBy(x: 0, y: 1)) {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        if !patternArea.contains(coordinate.offsetBy(x: -1, y: 0)) {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
    }

    private func drawSelection(in context: inout GraphicsContext, offset: GridCoordinate) {
        let selectionOffset = store.isMovingSelection ? store.selectionMovePreviewOffset : offset
        for coordinate in store.selection {
            let displayCoordinate = coordinate.offsetBy(x: selectionOffset.x, y: selectionOffset.y)
            let rect = rect(for: displayCoordinate).insetBy(dx: 1.5, dy: 1.5)
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.blue), lineWidth: 2)
        }
    }

    private func rect(for coordinate: GridCoordinate) -> CGRect {
        CGRect(x: CGFloat(coordinate.x) * cellSize, y: CGFloat(coordinate.y) * cellSize, width: cellSize, height: cellSize)
    }

}

private struct SewingAutoScrollView: UIViewRepresentable {
    var coordinate: GridCoordinate?
    var cellSize: CGFloat
    var contentPadding: CGFloat

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let coordinate else { return }
        scroll(to: coordinate, from: uiView, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            scroll(to: coordinate, from: uiView, animated: true)
        }
    }

    private func scroll(to coordinate: GridCoordinate, from view: UIView, animated: Bool) {
        guard let scrollView = view.enclosingScrollView else { return }

        let targetCenter = CGPoint(
            x: contentPadding + CGFloat(coordinate.x) * cellSize + cellSize / 2,
            y: contentPadding + CGFloat(coordinate.y) * cellSize + cellSize / 2
        )
        let desiredOffset = CGPoint(
            x: targetCenter.x - scrollView.bounds.width / 2,
            y: targetCenter.y - scrollView.bounds.height / 2
        )

        let inset = scrollView.adjustedContentInset
        let minOffset = CGPoint(x: -inset.left, y: -inset.top)
        let maxOffset = CGPoint(
            x: max(minOffset.x, scrollView.contentSize.width - scrollView.bounds.width + inset.right),
            y: max(minOffset.y, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        )
        let clampedOffset = CGPoint(
            x: min(max(desiredOffset.x, minOffset.x), maxOffset.x),
            y: min(max(desiredOffset.y, minOffset.y), maxOffset.y)
        )

        scrollView.setContentOffset(clampedOffset, animated: animated)
    }
}

private extension UIView {
    var enclosingScrollView: UIScrollView? {
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

private struct CellSymbolTemplates {
    var beadPath: Path
    var beadHighlightPath: Path
    var crossStitchPath: Path
    var satinStitchPath: Path

    init(cellSize: CGFloat) {
        let cellRect = CGRect(origin: .zero, size: CGSize(width: cellSize, height: cellSize))
        let beadRect = cellRect.insetBy(dx: cellSize * 0.07, dy: cellSize * 0.07)
        let crossStitchRect = cellRect.insetBy(dx: cellSize * 0.14, dy: cellSize * 0.14)

        beadPath = PatternCellSymbol.beadPath(in: beadRect)
        beadHighlightPath = PatternCellSymbol.beadHighlightPath(in: beadRect)

        var stitch = Path()
        stitch.move(to: CGPoint(x: crossStitchRect.minX, y: crossStitchRect.minY))
        stitch.addLine(to: CGPoint(x: crossStitchRect.maxX, y: crossStitchRect.maxY))
        stitch.move(to: CGPoint(x: crossStitchRect.maxX, y: crossStitchRect.minY))
        stitch.addLine(to: CGPoint(x: crossStitchRect.minX, y: crossStitchRect.maxY))
        crossStitchPath = stitch

        satinStitchPath = Path(cellRect)
    }
}

enum PatternCellSymbol {
    static func beadPath(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(245),
            endAngle: .degrees(385),
            clockwise: false
        )
        path.addLine(to: point(center: center, radius: radius, degrees: 65))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(65),
            endAngle: .degrees(205),
            clockwise: false
        )
        path.closeSubpath()

        return path
    }

    static func beadHighlightPath(in rect: CGRect) -> Path {
        var path = Path()
        let point = rectPoint(in: rect)

        path.move(to: point(0.28, 0.08))
        path.addCurve(to: point(0.89, 0.67), control1: point(0.56, 0.03), control2: point(0.96, 0.30))

        return path
    }

    private static func rectPoint(in rect: CGRect) -> (_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        { x, y in
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
    }

    private static func point(center: CGPoint, radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
    }
}

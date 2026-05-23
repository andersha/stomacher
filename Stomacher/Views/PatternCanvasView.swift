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
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let patternArea = store.document.activePatternArea()
                    drawBackground(in: &context, size: size)
                    drawOutsidePatternArea(in: &context, patternArea: patternArea)
                    drawCells(in: &context, patternArea: patternArea)
                    drawGrid(in: &context)
                    drawHiddenUnusedArea(in: &context, patternArea: patternArea)
                    drawOutline(in: &context, patternArea: patternArea)
                    drawSelection(in: &context)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(canvasBackground)

                DrawInputOverlay(
                    store: store,
                    cellSize: cellSize,
                    isEnabled: store.tool != .hand || store.moveMode == .pattern,
                    usesApplePencilOnly: supportsApplePencilEditing && store.usesApplePencilForEditing
                )
                .frame(width: canvasSize.width, height: canvasSize.height)
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

    private func drawCells(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?) {
        for (coordinate, swatchID) in store.document.cells {
            guard let swatch = store.document.swatch(for: swatchID) else { continue }
            guard patternArea?.contains(coordinate) ?? true else { continue }
            let cellRect = rect(for: coordinate)

            switch store.document.technique {
            case .beads:
                let beadRect = cellRect.insetBy(dx: cellSize * 0.02, dy: cellSize * 0.02)
                let beadPath = PatternCellSymbol.beadPath(in: beadRect)
                context.fill(beadPath, with: .color(swatch.color))
                context.stroke(beadPath, with: .color(.black.opacity(0.22)), lineWidth: max(0.7, cellSize * 0.045))
                context.stroke(PatternCellSymbol.beadHighlightPath(in: beadRect), with: .color(.white.opacity(0.28)), lineWidth: max(0.8, cellSize * 0.075))
            case .crossStitches:
                let rect = cellRect.insetBy(dx: cellSize * 0.14, dy: cellSize * 0.14)
                var stitch = Path()
                stitch.move(to: CGPoint(x: rect.minX, y: rect.minY))
                stitch.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                stitch.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                stitch.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                context.stroke(stitch, with: .color(swatch.color), lineWidth: max(1.5, cellSize * 0.2))
            case .satinStitch:
                context.fill(Path(cellRect), with: .color(swatch.color))
            }
        }
    }

    private func drawOutsidePatternArea(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?) {
        guard let patternArea else { return }
        guard !store.document.hideUnusedArea else { return }
        let outsideColor: Color = colorScheme == .dark ? .black.opacity(0.16) : .black.opacity(0.07)

        for y in 0..<store.document.height {
            for x in 0..<store.document.width {
                let coordinate = GridCoordinate(x: x, y: y)
                guard !patternArea.contains(coordinate) else { continue }
                context.fill(Path(rect(for: coordinate)), with: .color(outsideColor))
            }
        }
    }

    private func drawHiddenUnusedArea(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?) {
        guard let patternArea, store.document.hideUnusedArea else { return }

        for y in 0..<store.document.height {
            for x in 0..<store.document.width {
                let coordinate = GridCoordinate(x: x, y: y)
                guard !patternArea.contains(coordinate) else { continue }
                context.fill(Path(rect(for: coordinate)), with: .color(workspaceBackground))
            }
        }
    }

    private func drawOutline(in context: inout GraphicsContext, patternArea: Set<GridCoordinate>?) {
        guard store.document.hasCustomOutline else { return }
        let outlineColor: Color = patternArea == nil ? .orange : .red

        for coordinate in store.document.outlineCells {
            let rect = rect(for: coordinate).insetBy(dx: max(1, cellSize * 0.08), dy: max(1, cellSize * 0.08))
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(outlineColor), lineWidth: max(2, cellSize * 0.16))
        }
    }

    private func drawSelection(in context: inout GraphicsContext) {
        for coordinate in store.selection {
            let rect = rect(for: coordinate).insetBy(dx: 1.5, dy: 1.5)
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(.blue), lineWidth: 2)
        }
    }

    private func rect(for coordinate: GridCoordinate) -> CGRect {
        CGRect(x: CGFloat(coordinate.x) * cellSize, y: CGFloat(coordinate.y) * cellSize, width: cellSize, height: cellSize)
    }

}

enum PatternCellSymbol {
    static func beadPath(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let point = circlePoint(center: center, radius: radius)

        path.move(to: point(245))
        for degrees in stride(from: CGFloat(250), through: 385, by: 5) {
            path.addLine(to: point(degrees))
        }
        path.addLine(to: point(65))
        for degrees in stride(from: CGFloat(70), through: 205, by: 5) {
            path.addLine(to: point(degrees))
        }
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

    private static func circlePoint(center: CGPoint, radius: CGFloat) -> (_ degrees: CGFloat) -> CGPoint {
        { degrees in
            let radians = degrees * .pi / 180
            return CGPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
        }
    }
}

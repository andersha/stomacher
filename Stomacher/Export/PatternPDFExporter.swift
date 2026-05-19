import Foundation
import UIKit

struct PatternPDFExporter {
    private let pageRect = CGRect(x: 0, y: 0, width: 842, height: 595)
    private let margin: CGFloat = 36

    func export(document: PatternDocument) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(document.title.replacingOccurrences(of: " ", with: "-"))
            .appendingPathExtension("pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        try renderer.writePDF(to: url) { context in
            drawCover(document: document, context: context)
            drawPatternPages(document: document, context: context)
        }

        return url
    }

    private func drawCover(document: PatternDocument, context: UIGraphicsPDFRendererContext) {
        context.beginPage()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.label
        ]
        document.title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttributes)

        let outlineText = document.activePatternArea() == nil ? "rektangulær ytterkant" : "egen ytterkant"
        let meta = "\(document.technique.title) · \(document.width) x \(document.height) · \(document.cells.count) utfylte felt · \(outlineText)"
        meta.draw(at: CGPoint(x: margin, y: margin + 42), withAttributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ])

        drawLegend(document: document, origin: CGPoint(x: margin, y: margin + 86))
        drawOverview(document: document, rect: CGRect(x: 430, y: margin + 82, width: 360, height: 360))

        let note = "Utskriften bruker både farge og symbol slik at mønsteret kan leses selv når fargene er like eller skrives ut i gråtoner. Hver rute svarer til én \(document.technique.unitTitle)."
        note.draw(in: CGRect(x: margin, y: pageRect.height - 92, width: pageRect.width - margin * 2, height: 48), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    private func drawLegend(document: PatternDocument, origin: CGPoint) {
        "Fargekart".draw(at: origin, withAttributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.label
        ])

        var y = origin.y + 30
        for swatch in document.usedSwatches {
            let swatchRect = CGRect(x: origin.x, y: y, width: 20, height: 20)
            UIColor(hex: swatch.hex).setFill()
            UIBezierPath(rect: swatchRect).fill()
            UIColor.black.withAlphaComponent(0.25).setStroke()
            UIBezierPath(rect: swatchRect).stroke()

            "\(swatch.symbol)  \(swatch.name)  \(swatch.hex)".draw(at: CGPoint(x: origin.x + 32, y: y + 2), withAttributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.label
            ])
            y += 28
        }
    }

    private func drawOverview(document: PatternDocument, rect: CGRect) {
        UIColor.secondaryLabel.withAlphaComponent(0.16).setStroke()
        UIBezierPath(rect: rect).stroke()

        let scale = min(rect.width / CGFloat(document.width), rect.height / CGFloat(document.height))
        let drawnSize = CGSize(width: CGFloat(document.width) * scale, height: CGFloat(document.height) * scale)
        let origin = CGPoint(x: rect.midX - drawnSize.width / 2, y: rect.midY - drawnSize.height / 2)

        let patternArea = document.activePatternArea()

        if let patternArea {
            UIColor.systemGray.withAlphaComponent(0.10).setFill()
            for y in 0..<document.height {
                for x in 0..<document.width {
                    let coordinate = GridCoordinate(x: x, y: y)
                    guard !patternArea.contains(coordinate) else { continue }
                    let cell = CGRect(
                        x: origin.x + CGFloat(coordinate.x) * scale,
                        y: origin.y + CGFloat(coordinate.y) * scale,
                        width: max(0.5, scale),
                        height: max(0.5, scale)
                    )
                    UIBezierPath(rect: cell).fill()
                }
            }
        }

        for (coordinate, swatchID) in document.cells {
            guard patternArea?.contains(coordinate) ?? true else { continue }
            guard let swatch = document.swatch(for: swatchID) else { continue }
            UIColor(hex: swatch.hex).setFill()
            let cell = CGRect(
                x: origin.x + CGFloat(coordinate.x) * scale,
                y: origin.y + CGFloat(coordinate.y) * scale,
                width: max(0.5, scale),
                height: max(0.5, scale)
            )
            UIBezierPath(rect: cell).fill()
        }

        UIColor.systemRed.setStroke()
        for coordinate in document.outlineCells {
            let cell = CGRect(
                x: origin.x + CGFloat(coordinate.x) * scale,
                y: origin.y + CGFloat(coordinate.y) * scale,
                width: max(0.5, scale),
                height: max(0.5, scale)
            )
            let path = UIBezierPath(rect: cell)
            path.lineWidth = max(0.8, scale * 0.18)
            path.stroke()
        }
    }

    private func drawPatternPages(document: PatternDocument, context: UIGraphicsPDFRendererContext) {
        let cellsPerPageX = 48
        let cellsPerPageY = 32
        let bounds = document.printableBounds
        let pagesX = Int(ceil(Double(bounds.width) / Double(cellsPerPageX)))
        let pagesY = Int(ceil(Double(bounds.height) / Double(cellsPerPageY)))

        for pageY in 0..<pagesY {
            for pageX in 0..<pagesX {
                context.beginPage()
                drawPatternPage(
                    document: document,
                    bounds: bounds,
                    pageX: pageX,
                    pageY: pageY,
                    cellsPerPageX: cellsPerPageX,
                    cellsPerPageY: cellsPerPageY
                )
            }
        }
    }

    private func drawPatternPage(document: PatternDocument, bounds: GridBounds, pageX: Int, pageY: Int, cellsPerPageX: Int, cellsPerPageY: Int) {
        let startX = bounds.minX + pageX * cellsPerPageX
        let startY = bounds.minY + pageY * cellsPerPageY
        let endX = min(bounds.maxX + 1, startX + cellsPerPageX)
        let endY = min(bounds.maxY + 1, startY + cellsPerPageY)
        let visibleWidth = endX - startX
        let visibleHeight = endY - startY
        let patternArea = document.activePatternArea()

        let title = "\(document.title) · side \(pageY + 1)-\(pageX + 1)"
        title.draw(at: CGPoint(x: margin, y: 22), withAttributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.label
        ])

        let gridRect = CGRect(x: margin, y: 54, width: pageRect.width - margin * 2, height: pageRect.height - 96)
        let cellSize = min(gridRect.width / CGFloat(cellsPerPageX), gridRect.height / CGFloat(cellsPerPageY))
        let origin = CGPoint(x: gridRect.minX, y: gridRect.minY)

        for y in 0..<visibleHeight {
            for x in 0..<visibleWidth {
                let documentCoordinate = GridCoordinate(x: startX + x, y: startY + y)
                let rect = CGRect(
                    x: origin.x + CGFloat(x) * cellSize,
                    y: origin.y + CGFloat(y) * cellSize,
                    width: cellSize,
                    height: cellSize
                )

                if let swatchID = document.cells[documentCoordinate], let swatch = document.swatch(for: swatchID) {
                    guard patternArea?.contains(documentCoordinate) ?? true else { continue }
                    UIColor(hex: swatch.hex).withAlphaComponent(0.62).setFill()
                    UIBezierPath(rect: rect).fill()
                    drawSymbol(swatch.symbol, in: rect)
                } else if let patternArea, !patternArea.contains(documentCoordinate) {
                    UIColor.systemGray.withAlphaComponent(0.14).setFill()
                    UIBezierPath(rect: rect).fill()
                }
            }
        }

        drawGrid(rect: CGRect(x: origin.x, y: origin.y, width: CGFloat(visibleWidth) * cellSize, height: CGFloat(visibleHeight) * cellSize), cellSize: cellSize, columns: visibleWidth, rows: visibleHeight)
        drawOutline(document: document, origin: origin, startX: startX, startY: startY, visibleWidth: visibleWidth, visibleHeight: visibleHeight, cellSize: cellSize)

        let footer = "Kolonner \(startX)-\(endX - 1), rader \(startY)-\(endY - 1)"
        footer.draw(at: CGPoint(x: margin, y: pageRect.height - 32), withAttributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
        ])
    }

    private func drawSymbol(_ symbol: String, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: max(7, rect.height * 0.42), weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        let size = symbol.size(withAttributes: attributes)
        symbol.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private func drawOutline(document: PatternDocument, origin: CGPoint, startX: Int, startY: Int, visibleWidth: Int, visibleHeight: Int, cellSize: CGFloat) {
        guard document.hasCustomOutline else { return }

        UIColor.systemRed.setStroke()
        for coordinate in document.outlineCells {
            guard coordinate.x >= startX, coordinate.x < startX + visibleWidth else { continue }
            guard coordinate.y >= startY, coordinate.y < startY + visibleHeight else { continue }

            let rect = CGRect(
                x: origin.x + CGFloat(coordinate.x - startX) * cellSize,
                y: origin.y + CGFloat(coordinate.y - startY) * cellSize,
                width: cellSize,
                height: cellSize
            ).insetBy(dx: cellSize * 0.10, dy: cellSize * 0.10)
            let path = UIBezierPath(rect: rect)
            path.lineWidth = max(1.2, cellSize * 0.14)
            path.stroke()
        }
    }

    private func drawGrid(rect: CGRect, cellSize: CGFloat, columns: Int, rows: Int) {
        let gridPath = UIBezierPath()
        for x in 0...columns {
            let px = rect.minX + CGFloat(x) * cellSize
            gridPath.move(to: CGPoint(x: px, y: rect.minY))
            gridPath.addLine(to: CGPoint(x: px, y: rect.maxY))
        }
        for y in 0...rows {
            let py = rect.minY + CGFloat(y) * cellSize
            gridPath.move(to: CGPoint(x: rect.minX, y: py))
            gridPath.addLine(to: CGPoint(x: rect.maxX, y: py))
        }
        UIColor.black.withAlphaComponent(0.24).setStroke()
        gridPath.lineWidth = 0.5
        gridPath.stroke()

        let majorPath = UIBezierPath()
        for x in stride(from: 0, through: columns, by: 10) {
            let px = rect.minX + CGFloat(x) * cellSize
            majorPath.move(to: CGPoint(x: px, y: rect.minY))
            majorPath.addLine(to: CGPoint(x: px, y: rect.maxY))
        }
        for y in stride(from: 0, through: rows, by: 10) {
            let py = rect.minY + CGFloat(y) * cellSize
            majorPath.move(to: CGPoint(x: rect.minX, y: py))
            majorPath.addLine(to: CGPoint(x: rect.maxX, y: py))
        }
        UIColor.black.withAlphaComponent(0.52).setStroke()
        majorPath.lineWidth = 1
        majorPath.stroke()
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

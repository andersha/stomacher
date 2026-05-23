import SwiftUI

enum PatternTechnique: String, Codable, CaseIterable, Identifiable {
    case beads
    case crossStitches = "stitches"
    case satinStitch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beads: "Perler"
        case .crossStitches: "Korssting"
        case .satinStitch: "Plattsøm"
        }
    }

    var unitTitle: String {
        switch self {
        case .beads: "perle"
        case .crossStitches: "korssting"
        case .satinStitch: "plattsømsting"
        }
    }
}

struct PaletteSwatch: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var hex: String
    var symbol: String

    var color: Color {
        Color(hex: hex) ?? .black
    }

    static let defaultPalette: [PaletteSwatch] = [
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Hvit", hex: "#F8F4EA", symbol: "A"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Burgunder", hex: "#7A1834", symbol: "B"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Rosa", hex: "#C86A86", symbol: "C"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "Sort", hex: "#151515", symbol: "D"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "Gull", hex: "#B99A2C", symbol: "E"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!, name: "Grønn", hex: "#1F6A45", symbol: "F"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!, name: "Blå", hex: "#244B9B", symbol: "G"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!, name: "Rød", hex: "#B3262E", symbol: "H"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!, name: "Lys rød", hex: "#E36B6F", symbol: "I"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, name: "Gul", hex: "#F1C84B", symbol: "J"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!, name: "Lys grønn", hex: "#8BCF8B", symbol: "K"),
        PaletteSwatch(id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!, name: "Lys blå", hex: "#78B7E5", symbol: "L")
    ]
}

struct PatternPalette: Identifiable, Codable, Hashable {
    static let standardID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let standardName = "Standard"

    static let builtInPalettes = [
        PatternPalette(id: standardID, name: standardName, swatches: PaletteSwatch.defaultPalette)
    ]

    var id: UUID
    var name: String
    var swatches: [PaletteSwatch]

    var isBuiltIn: Bool {
        Self.builtInPalettes.contains { $0.id == id }
    }

    static func normalizedSwatches(_ swatches: [PaletteSwatch]) -> [PaletteSwatch] {
        PaletteSwatch.defaultPalette.enumerated().map { index, defaultSwatch in
            let source = swatches.first { $0.symbol == defaultSwatch.symbol } ?? swatches[safe: index] ?? defaultSwatch
            return PaletteSwatch(
                id: defaultSwatch.id,
                name: source.name.isEmpty ? defaultSwatch.name : source.name,
                hex: PaletteColor(hex: source.hex)?.hex ?? defaultSwatch.hex,
                symbol: defaultSwatch.symbol
            )
        }
    }
}

struct PaletteColor: Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = hue.clamped(to: 0...1)
        let s = saturation.clamped(to: 0...1)
        let v = brightness.clamped(to: 0...1)

        guard s > 0 else {
            self.init(red: v, green: v, blue: v)
            return
        }

        let scaledHue = h * 6
        let sector = Int(floor(scaledHue))
        let fraction = scaledHue - Double(sector)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))

        switch sector % 6 {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let h = hue.clamped(to: 0...1)
        let s = saturation.clamped(to: 0...1)
        let l = lightness.clamped(to: 0...1)

        guard s > 0 else {
            self.init(red: l, green: l, blue: l)
            return
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hueToRGB(_ value: Double) -> Double {
            var t = value
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        self.init(
            red: hueToRGB(h + 1.0 / 3.0),
            green: hueToRGB(h),
            blue: hueToRGB(h - 1.0 / 3.0)
        )
    }

    init(cyan: Double, magenta: Double, yellow: Double, black: Double) {
        let c = cyan.clamped(to: 0...1)
        let m = magenta.clamped(to: 0...1)
        let y = yellow.clamped(to: 0...1)
        let k = black.clamped(to: 0...1)

        self.init(
            red: (1 - c) * (1 - k),
            green: (1 - m) * (1 - k),
            blue: (1 - y) * (1 - k)
        )
    }

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var rgb255: (red: Int, green: Int, blue: Int) {
        (
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var hsv: (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum

        let hue: Double
        if delta == 0 {
            hue = 0
        } else if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maximum == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }

        return (
            hue < 0 ? hue + 1 : hue,
            maximum == 0 ? 0 : delta / maximum,
            maximum
        )
    }

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2

        guard delta > 0 else {
            return (0, 0, lightness)
        }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        return (hsv.hue, saturation, lightness)
    }

    var cmyk: (cyan: Double, magenta: Double, yellow: Double, black: Double) {
        let black = 1 - max(red, green, blue)
        guard black < 1 else { return (0, 0, 0, 1) }

        return (
            (1 - red - black) / (1 - black),
            (1 - green - black) / (1 - black),
            (1 - blue - black) / (1 - black),
            black
        )
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

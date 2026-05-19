import SwiftUI

enum PatternTechnique: String, Codable, CaseIterable, Identifiable {
    case beads
    case stitches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beads: "Perler"
        case .stitches: "Masker"
        }
    }

    var unitTitle: String {
        switch self {
        case .beads: "perle"
        case .stitches: "maske"
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

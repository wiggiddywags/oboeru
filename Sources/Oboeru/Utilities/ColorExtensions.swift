import SwiftUI

extension Color {
    /// Initializes a Color from a hex string like "#FF6B6B" or "FF6B6B".
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double((value      ) & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension UUID {
    /// Sentinel value used to store the "all decks" due count in DeckListViewModel.dueCounts.
    static var zero: UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000000")! }
}

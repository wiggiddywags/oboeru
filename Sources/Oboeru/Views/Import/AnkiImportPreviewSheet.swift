import SwiftUI
import SwiftData

struct AnkiImportPreviewSheet: View {

    let url: URL
    let modelContext: ModelContext
    let onDismiss: () -> Void

    @State private var decks: [AnkiImportDeck] = []
    @State private var isLoading = true
    @State private var error: String? = nil
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Anki")
                        .font(.title2).fontWeight(.semibold)
                    Text(url.lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onDismiss)
            }
            .padding(20)

            Divider()

            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading .apkg file…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 36)).foregroundStyle(.red)
                        Text("Import Failed").font(.headline)
                        Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Summary
                            let totalCards = decks.reduce(0) { $0 + $1.cards.count }
                            HStack(spacing: 20) {
                                summaryTile(value: "\(decks.count)", label: "Decks", color: .accentColor)
                                summaryTile(value: "\(totalCards)", label: "Cards", color: .green)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)

                            // Per-deck breakdown
                            ForEach(decks.indices, id: \.self) { i in
                                let deck = decks[i]
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: deck.colorHex) ?? .accentColor)
                                        .frame(width: 10, height: 10)
                                    Text(deck.name).fontWeight(.medium)
                                    Spacer()
                                    Text("\(deck.cards.count) cards")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 20)

                                // Preview first 3 cards
                                ForEach(deck.cards.prefix(3).indices, id: \.self) { j in
                                    let card = deck.cards[j]
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(card.cardType == .cloze ? "C" : "Q")
                                            .font(.caption2).fontWeight(.bold)
                                            .foregroundStyle(.white)
                                            .frame(width: 16, height: 16)
                                            .background(card.cardType == .cloze ? Color.purple : Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(card.frontText.prefix(80)).font(.caption).lineLimit(1)
                                            if !card.backText.isEmpty {
                                                Text(card.backText.prefix(80)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 36)
                                }
                                if deck.cards.count > 3 {
                                    Text("  …and \(deck.cards.count - 3) more")
                                        .font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 36)
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Import \(decks.reduce(0) { $0 + $1.cards.count }) Cards") {
                    doImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(decks.isEmpty || isImporting || isLoading)
            }
            .padding(16)
        }
        .frame(width: 520, height: 480)
        .task { await loadPreview() }
    }

    private func summaryTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        let localURL = url
        let ok = localURL.startAccessingSecurityScopedResource()
        defer { if ok { localURL.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try AnkiImporter.import(from: localURL)
            }.value
            decks = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func doImport() {
        isImporting = true
        for ankiDeck in decks {
            let deck = Deck(name: ankiDeck.name, colorHex: ankiDeck.colorHex)
            modelContext.insert(deck)
            for ac in ankiDeck.cards {
                if ac.cardType == .cloze, let clozeText = ac.clozeText {
                    let siblings = ClozeParser.siblings(for: clozeText)
                    for s in siblings {
                        let card = OboerCard(deck: deck, cardType: .cloze,
                                            frontText: s.maskedText, backText: s.fullText,
                                            clozeText: clozeText, clozeOrdinal: s.ordinal)
                        card.tags = ac.tags
                        modelContext.insert(card)
                    }
                } else {
                    let card = OboerCard(deck: deck, cardType: .basic,
                                        frontText: ac.frontText, backText: ac.backText)
                    card.tags = ac.tags
                    modelContext.insert(card)
                }
            }
        }
        try? modelContext.save()
        onDismiss()
    }
}

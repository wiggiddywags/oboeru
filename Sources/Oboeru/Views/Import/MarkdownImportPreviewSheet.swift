import SwiftUI
import SwiftData

struct MarkdownImportPreviewSheet: View {

    let url: URL
    let modelContext: ModelContext
    let onDismiss: () -> Void

    @State private var cards: [MarkdownImportCard] = []
    @State private var deckName: String = ""
    @State private var isLoading = true
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from Markdown")
                        .font(.title2).fontWeight(.semibold)
                    Text(url.lastPathComponent)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", action: onDismiss)
            }
            .padding(20)

            Divider()

            contentArea

            Divider()

            HStack {
                Spacer()
                Button("Import \(cards.count) Cards") {
                    doImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(cards.isEmpty || deckName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 500)
        .task { await loadPreview() }
    }

    @ViewBuilder
    private var contentArea: some View {
        if isLoading {
            ProgressView("Parsing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = error {
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 36)).foregroundStyle(.red)
                Text("Parse Failed").font(.headline)
                Text(err).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Deck Name").font(.caption).foregroundStyle(.secondary)
                        TextField("Deck name…", text: $deckName)
                            .textFieldStyle(.roundedBorder)
                    }
                    summaryTile(value: "\(cards.count)", label: "Cards", color: .accentColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                List(Array(cards.enumerated()), id: \.offset) { _, card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.frontText)
                            .font(.subheadline).fontWeight(.medium).lineLimit(2)
                        Text(card.backText)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if !card.tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(card.tags, id: \.self) { tag in
                                    Text("#\(tag)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func summaryTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 80)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        let localURL = url
        let baseName = localURL.deletingPathExtension().lastPathComponent
        deckName = baseName
        let ok = localURL.startAccessingSecurityScopedResource()
        defer { if ok { localURL.stopAccessingSecurityScopedResource() } }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try MarkdownImporter.import(from: localURL)
            }.value
            cards = result
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func doImport() {
        let name = deckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let deck = Deck(name: name)
        modelContext.insert(deck)
        for mc in cards {
            let card = OboerCard(deck: deck, cardType: .basic,
                                 frontText: mc.frontText, backText: mc.backText)
            card.tags = mc.tags
            modelContext.insert(card)
        }
        try? modelContext.save()
        onDismiss()
    }
}

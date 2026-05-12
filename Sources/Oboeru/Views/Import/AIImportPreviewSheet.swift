import SwiftUI
import SwiftData

// MARK: - Preview sheet (shared by Document & URL import)

struct AIImportPreviewSheet: View {

    let sourceTitle:  String
    let allDecks:     [Deck]
    let defaultDeck:  Deck?
    let modelContext: ModelContext
    let onDismiss:    () -> Void

    @State private var cards:         [AIGeneratedCard]
    @State private var selectedDeckID: UUID?
    @State private var filter:         String = "all"  // "all" | "beginner" | "intermediate" | "advanced"

    init(cards: [AIGeneratedCard], sourceTitle: String, allDecks: [Deck],
         defaultDeck: Deck?, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        _cards          = State(initialValue: cards)
        self.sourceTitle  = sourceTitle
        self.allDecks     = allDecks
        self.defaultDeck  = defaultDeck
        self.modelContext = modelContext
        self.onDismiss    = onDismiss
        _selectedDeckID  = State(initialValue: defaultDeck?.id)
    }

    private var included: [AIGeneratedCard] { cards.filter(\.isIncluded) }
    private var targetDeck: Deck? { allDecks.first { $0.id == selectedDeckID } }

    private var visible: [AIGeneratedCard] {
        filter == "all" ? cards : cards.filter { $0.difficulty == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            cardList
            Divider()
            footer
        }
        .frame(width: 740, height: 620)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review Generated Cards")
                    .font(.title2).fontWeight(.semibold)
                Text(sourceTitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 20) {
                statPill(value: included.count, label: "selected", color: .accentColor)
                statPill(value: included.filter { $0.type == "basic"  }.count, label: "basic",  color: .blue)
                statPill(value: included.filter { $0.type == "cloze"  }.count, label: "cloze",  color: .purple)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $filter) {
                Text("All").tag("all")
                Text("Beginner").tag("beginner")
                Text("Intermediate").tag("intermediate")
                Text("Advanced").tag("advanced")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            Spacer()

            Button("Select All")   { cards.indices.forEach { cards[$0].isIncluded = true  } }
            Button("Deselect All") { cards.indices.forEach { cards[$0].isIncluded = false } }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Card list

    private var cardList: some View {
        List {
            ForEach($cards) { $card in
                if filter == "all" || card.difficulty == filter {
                    AICardPreviewRow(card: $card)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onDismiss)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.secondary).font(.caption)
                Text("Add to:")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("", selection: $selectedDeckID) {
                    Text("Choose a deck…").tag(UUID?.none)
                    ForEach(allDecks) { deck in
                        HStack {
                            Image(systemName: deck.iconName)
                            Text(deck.name)
                        }
                        .tag(Optional(deck.id))
                    }
                }
                .frame(width: 200)
            }

            Button {
                saveCards()
            } label: {
                Label("Save \(included.count) Card\(included.count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(included.isEmpty || targetDeck == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Save

    private func saveCards() {
        guard let deck = targetDeck else { return }
        for card in included {
            let oboerCard: OboerCard
            if card.type == "cloze" {
                oboerCard = OboerCard(deck: deck, cardType: .cloze,
                                      frontText: card.front, backText: "",
                                      clozeText: card.front, clozeOrdinal: 0)
            } else {
                oboerCard = OboerCard(deck: deck, cardType: .basic,
                                      frontText: card.front, backText: card.back)
            }
            oboerCard.tags = card.tags
            modelContext.insert(oboerCard)
        }
        try? modelContext.save()
        onDismiss()
    }

    // MARK: - Helpers

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Card row

private struct AICardPreviewRow: View {

    @Binding var card: AIGeneratedCard
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $card.isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                // Badges
                HStack(spacing: 5) {
                    badge(card.type.capitalized,      color: card.type == "cloze" ? .purple : .blue)
                    badge(card.difficulty.capitalized, color: difficultyColor)
                    ForEach(card.tags, id: \.self) { badge($0, color: .secondary) }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.2)) { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                if isEditing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Front").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $card.front)
                            .font(.callout).frame(minHeight: 48, maxHeight: 80)
                            .padding(4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        if card.type == "basic" {
                            Text("Back").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $card.back)
                                .font(.callout).frame(minHeight: 48, maxHeight: 80)
                                .padding(4)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text(card.front)
                        .font(.callout)
                        .lineLimit(2)
                        .foregroundStyle(card.isIncluded ? .primary : .secondary)
                    if !card.back.isEmpty {
                        Text(card.back)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .opacity(card.isIncluded ? 1 : 0.4)
        .padding(.vertical, 3)
    }

    private var difficultyColor: Color {
        switch card.difficulty {
        case "beginner":     return .green
        case "intermediate": return .orange
        case "advanced":     return .red
        default:             return .secondary
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

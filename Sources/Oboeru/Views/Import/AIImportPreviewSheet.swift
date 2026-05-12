import SwiftUI
import SwiftData

// MARK: - Preview sheet (shared by Document & URL import)

struct AIImportPreviewSheet: View {

    let sourceTitle:  String
    let allDecks:     [Deck]
    let defaultDeck:  Deck?
    let modelContext: ModelContext
    let onDismiss:    () -> Void

    @State private var cards: [AIGeneratedCard]
    @State private var filter: String = "all"

    // Destination state
    @State private var destMode: DestMode = .existing
    @State private var selectedDeckID: UUID?    // existing-deck mode
    @State private var newDeckName  = ""        // new-deck + split modes
    @State private var newDeckColor = "#5E9CF0" // new-deck + split modes
    @State private var newParentID: UUID? = nil // new-deck mode: optional parent

    enum DestMode: String, CaseIterable {
        case existing = "Existing Deck"
        case newDeck  = "New Deck"
        case split    = "New Deck + Sub-decks"
    }

    private static let palette = [
        "#5E9CF0", "#FF6B6B", "#51CF66", "#FF922B",
        "#CC5DE8", "#20C997", "#F59F00", "#74C0FC"
    ]

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

    private var canSave: Bool {
        guard !included.isEmpty else { return false }
        switch destMode {
        case .existing: return selectedDeckID != nil
        case .newDeck, .split: return !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            Divider()
            cardList
            Divider()
            destinationSection
            Divider()
            actionRow
        }
        .frame(width: 760, height: 700)
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
                statPill(value: included.count,                                       label: "selected",  color: .accentColor)
                statPill(value: included.filter { $0.type == "basic"  }.count,        label: "basic",     color: .blue)
                statPill(value: included.filter { $0.type == "cloze"  }.count,        label: "cloze",     color: .purple)
                statPill(value: included.filter { $0.difficulty == "beginner"     }.count, label: "beginner",  color: .green)
                statPill(value: included.filter { $0.difficulty == "intermediate" }.count, label: "mid",       color: .orange)
                statPill(value: included.filter { $0.difficulty == "advanced"     }.count, label: "advanced",  color: .red)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
            .pickerStyle(.segmented).labelsHidden().frame(width: 320)

            Spacer()

            Button("Select All")   { cards.indices.forEach { cards[$0].isIncluded = true  } }
            Button("Deselect All") { cards.indices.forEach { cards[$0].isIncluded = false } }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
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

    // MARK: - Destination section

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode selector
            HStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.secondary).font(.caption)
                Text("Save to:")
                    .font(.callout).fontWeight(.medium)
                Picker("", selection: $destMode) {
                    ForEach(DestMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 380)
                .onChange(of: destMode) { _, _ in newDeckName = ""; newParentID = nil }
            }

            // Mode-specific controls
            switch destMode {
            case .existing:
                existingDeckPicker

            case .newDeck:
                newDeckControls(showParentPicker: true)

            case .split:
                VStack(alignment: .leading, spacing: 10) {
                    newDeckControls(showParentPicker: false)
                    // Preview of what will be created
                    if !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty {
                        splitPreview
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }

    private var existingDeckPicker: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selectedDeckID) {
                Text("Choose a deck…").tag(UUID?.none)
                // Top-level decks
                ForEach(allDecks.filter { $0.parentDeckID == nil }) { deck in
                    Label(deck.name, systemImage: deck.iconName).tag(Optional(deck.id))
                }
                // Sub-decks grouped under their parents
                ForEach(allDecks.filter { $0.parentDeckID != nil }) { deck in
                    let parentName = allDecks.first(where: { $0.id == deck.parentDeckID })?.name ?? ""
                    Text("  ↳ \(parentName) › \(deck.name)").tag(Optional(deck.id))
                }
            }
            .frame(maxWidth: 360)

            if let deck = allDecks.first(where: { $0.id == selectedDeckID }) {
                Label("\(deck.cards.count) existing cards", systemImage: "rectangle.stack")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func newDeckControls(showParentPicker: Bool) -> some View {
        HStack(spacing: 12) {
            TextField("Deck name…", text: $newDeckName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            // Color palette
            HStack(spacing: 6) {
                ForEach(Self.palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .blue)
                        .frame(width: 22, height: 22)
                        .overlay {
                            if hex == newDeckColor {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .onTapGesture { newDeckColor = hex }
                }
            }

            if showParentPicker {
                Divider().frame(height: 24)
                HStack(spacing: 6) {
                    Text("Sub-deck of:")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $newParentID) {
                        Text("None (top-level)").tag(UUID?.none)
                        ForEach(allDecks.filter { $0.parentDeckID == nil }) { deck in
                            Label(deck.name, systemImage: deck.iconName).tag(Optional(deck.id))
                        }
                    }
                    .frame(width: 160)
                }
            }
        }
    }

    private var splitPreview: some View {
        let name = newDeckName.trimmingCharacters(in: .whitespaces)
        let bCount = included.filter { $0.difficulty == "beginner"     }.count
        let mCount = included.filter { $0.difficulty == "intermediate" }.count
        let aCount = included.filter { $0.difficulty == "advanced"     }.count

        return HStack(spacing: 16) {
            Label("Will create:", systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(name).fontWeight(.semibold)
                Text("›")
                diffBadge("Beginner · \(bCount)",     color: .green)
                diffBadge("Intermediate · \(mCount)", color: .orange)
                diffBadge("Advanced · \(aCount)",     color: .red)
            }
            .font(.caption)
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onDismiss)
            Spacer()
            Button {
                saveCards()
            } label: {
                Label("Save \(included.count) Card\(included.count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Save logic

    private func saveCards() {
        switch destMode {

        case .existing:
            guard let deck = allDecks.first(where: { $0.id == selectedDeckID }) else { return }
            insertCards(included, into: deck)

        case .newDeck:
            let name = newDeckName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let deck = Deck(name: name, colorHex: newDeckColor,
                            iconName: "rectangle.stack", parentDeckID: newParentID)
            deck.sortOrder = 999
            modelContext.insert(deck)
            insertCards(included, into: deck)

        case .split:
            let name = newDeckName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            // Parent deck
            let parent = Deck(name: name, colorHex: newDeckColor, iconName: "rectangle.stack")
            parent.sortOrder = 999
            modelContext.insert(parent)

            // Sub-decks
            let subs: [(key: String, label: String, color: String, icon: String, order: Int)] = [
                ("beginner",     "Beginner",     "#51CF66", "1.circle.fill", 0),
                ("intermediate", "Intermediate", "#FF922B", "2.circle.fill", 1),
                ("advanced",     "Advanced",     "#FF6B6B", "3.circle.fill", 2),
            ]
            var deckByDifficulty: [String: Deck] = [:]
            for sub in subs {
                let d = Deck(name: sub.label, colorHex: sub.color,
                             iconName: sub.icon, parentDeckID: parent.id)
                d.sortOrder = sub.order
                modelContext.insert(d)
                deckByDifficulty[sub.key] = d
            }

            // Route each card by difficulty; unmapped → beginner
            for card in included {
                let target = deckByDifficulty[card.difficulty] ?? deckByDifficulty["beginner"]!
                insertCard(card, into: target)
            }
        }

        try? modelContext.save()
        onDismiss()
    }

    private func insertCards(_ cards: [AIGeneratedCard], into deck: Deck) {
        for card in cards { insertCard(card, into: deck) }
    }

    private func insertCard(_ card: AIGeneratedCard, into deck: Deck) {
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

    // MARK: - Helpers

    private func statPill(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(value)").font(.title3).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func diffBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Card row

private struct AICardPreviewRow: View {

    @Binding var card: AIGeneratedCard
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: $card.isIncluded)
                .toggleStyle(.checkbox).labelsHidden().padding(.top, 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    badge(card.type.capitalized,       color: card.type == "cloze" ? .purple : .blue)
                    badge(card.difficulty.capitalized,  color: difficultyColor)
                    ForEach(card.tags, id: \.self) { badge($0, color: .secondary) }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.2)) { isEditing.toggle() }
                    } label: {
                        Image(systemName: isEditing ? "checkmark" : "pencil").font(.caption)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }

                if isEditing {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Front").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $card.front)
                            .font(.callout).frame(minHeight: 48, maxHeight: 80)
                            .padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        if card.type == "basic" {
                            Text("Back").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $card.back)
                                .font(.callout).frame(minHeight: 48, maxHeight: 80)
                                .padding(4).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text(card.front)
                        .font(.callout).lineLimit(2)
                        .foregroundStyle(card.isIncluded ? .primary : .secondary)
                    if !card.back.isEmpty {
                        Text(card.back).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            .font(.caption2).fontWeight(.medium).foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

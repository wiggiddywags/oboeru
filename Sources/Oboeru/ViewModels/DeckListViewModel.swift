import Foundation
import SwiftData

@Observable
final class DeckListViewModel {

    private(set) var decks: [Deck] = []
    private(set) var dueCounts: [UUID: Int] = [:]
    var selectedDeckID: UUID?
    var isShowingNewDeckSheet = false
    var editingDeck: Deck? = nil   // non-nil when editing an existing deck

    private let modelContext: ModelContext
    private let statsService: StatsService
    private let fsrsService: FSRSService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.statsService = StatsService(modelContext: modelContext)
        self.fsrsService = FSRSService()
    }

    // MARK: - Load

    func load() {
        let descriptor = FetchDescriptor<Deck>(
            predicate: #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        decks = (try? modelContext.fetch(descriptor)) ?? []
        refreshDueCounts()
    }

    /// Reorder decks within a group (top-level when parentID is nil, or sub-decks of a given parent).
    func moveDecks(from offsets: IndexSet, to destination: Int, parentID: UUID?) {
        var group: [Deck]
        if let pid = parentID {
            group = decks.filter { $0.parentDeckID == pid }
        } else {
            group = topLevelDecks
        }
        group.move(fromOffsets: offsets, toOffset: destination)
        for (index, deck) in group.enumerated() {
            deck.sortOrder = index
        }
        try? modelContext.save()
        load()
    }

    func refreshDueCounts() {
        var counts: [UUID: Int] = [:]
        for deck in decks {
            counts[deck.id] = deck.dueCards.count
        }
        // Roll up sub-deck counts into parent counts
        for deck in decks where deck.parentDeckID == nil {
            let childCount = subDecks(of: deck).reduce(0) { $0 + (counts[$1.id] ?? 0) }
            counts[deck.id] = (counts[deck.id] ?? 0) + childCount
        }
        // All-decks count stored under UUID.zero as a sentinel
        counts[.zero] = decks.filter { $0.parentDeckID == nil }.compactMap { counts[$0.id] }.reduce(0, +)
        dueCounts = counts
    }

    // MARK: - CRUD

    @discardableResult
    func createDeck(name: String, colorHex: String = "#5E9CF0", iconName: String = "rectangle.stack", parentDeckID: UUID? = nil) -> Deck {
        let deck = Deck(name: name, colorHex: colorHex, iconName: iconName, parentDeckID: parentDeckID)
        // Place new deck at the end of its group
        let siblings = parentDeckID == nil ? topLevelDecks : decks.filter { $0.parentDeckID == parentDeckID }
        deck.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        modelContext.insert(deck)
        try? modelContext.save()
        load()
        return deck
    }

    /// Returns the deck and all its immediate sub-decks.
    func decksForStudy(parentID: UUID) -> [Deck] {
        guard let parent = decks.first(where: { $0.id == parentID }) else { return [] }
        let children = decks.filter { $0.parentDeckID == parentID }
        return [parent] + children
    }

    /// Returns all sub-decks of a deck recursively.
    func subDecks(of parent: Deck) -> [Deck] {
        let direct = decks.filter { $0.parentDeckID == parent.id }
        return direct + direct.flatMap { subDecks(of: $0) }
    }

    /// Top-level decks (no parent)
    var topLevelDecks: [Deck] {
        decks.filter { $0.parentDeckID == nil }
    }

    func deleteDeck(_ deck: Deck) {
        modelContext.delete(deck)
        try? modelContext.save()
        if selectedDeckID == deck.id { selectedDeckID = nil }
        load()
    }

    func archiveDeck(_ deck: Deck) {
        deck.isArchived = true
        try? modelContext.save()
        load()
    }

    func updateDeck(_ deck: Deck, name: String, colorHex: String, iconName: String, parentDeckID: UUID? = nil) {
        deck.name         = name
        deck.colorHex     = colorHex
        deck.iconName     = iconName
        deck.parentDeckID = parentDeckID
        try? modelContext.save()
        load()
    }

    func save() {
        try? modelContext.save()
    }

    // MARK: - Start study session

    func makeStudySession(for targetDeckID: UUID?, settings: AppSettings) -> StudySession {
        let targetDecks: [Deck]
        if let id = targetDeckID, let deck = decks.first(where: { $0.id == id }) {
            // Include sub-decks automatically
            targetDecks = [deck] + subDecks(of: deck)
        } else {
            targetDecks = decks   // study all
        }
        return StudySession(
            decks: targetDecks,
            settings: settings,
            fsrsService: fsrsService,
            modelContext: modelContext
        )
    }

    var selectedDeck: Deck? {
        guard let id = selectedDeckID else { return nil }
        return decks.first { $0.id == id }
    }
}

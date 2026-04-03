import Foundation
import SwiftData

@Observable
final class DeckListViewModel {

    private(set) var decks: [Deck] = []
    private(set) var dueCounts: [UUID: Int] = [:]
    var selectedDeckID: UUID?
    var isShowingNewDeckSheet = false

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
            sortBy: [SortDescriptor(\.createdAt)]
        )
        decks = (try? modelContext.fetch(descriptor)) ?? []
        refreshDueCounts()
    }

    func refreshDueCounts() {
        let now = Date()
        var counts: [UUID: Int] = [:]
        for deck in decks {
            counts[deck.id] = deck.dueCards.count
        }
        // All-decks count stored under UUID.zero as a sentinel
        counts[.zero] = counts.values.reduce(0, +)
        dueCounts = counts
    }

    // MARK: - CRUD

    func createDeck(name: String, colorHex: String = "#5E9CF0", iconName: String = "rectangle.stack") {
        let deck = Deck(name: name, colorHex: colorHex, iconName: iconName)
        modelContext.insert(deck)
        try? modelContext.save()
        load()
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

    // MARK: - Start study session

    func makeStudySession(for targetDeckID: UUID?, settings: AppSettings) -> StudySession {
        let targetDecks: [Deck]
        if let id = targetDeckID, let deck = decks.first(where: { $0.id == id }) {
            targetDecks = [deck]
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

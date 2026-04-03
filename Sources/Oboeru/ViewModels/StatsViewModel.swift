import Foundation
import SwiftData

@Observable
final class StatsViewModel {

    private(set) var snapshot: StatsSnapshot?
    private(set) var isLoading = false
    var selectedDeckIDs: Set<UUID> = []     // empty = all decks

    private let statsService: StatsService
    private let settings: AppSettings

    init(modelContext: ModelContext, settings: AppSettings) {
        self.statsService = StatsService(modelContext: modelContext)
        self.settings = settings
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let ids = selectedDeckIDs.isEmpty ? nil : selectedDeckIDs
        snapshot = try? statsService.snapshot(deckIDs: ids, settings: settings)
    }
}

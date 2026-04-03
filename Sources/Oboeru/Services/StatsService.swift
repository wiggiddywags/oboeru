import Foundation
import SwiftData

struct DailyActivity: Identifiable {
    let id = UUID()
    let date: Date
    let reviewed: Int
    let newCards: Int
    let retentionRate: Double    // 0–1
}

struct StatsSnapshot {
    let retentionRate: Double        // rolling 30-day
    let currentStreak: Int
    let dueToday: Int
    let totalCards: Int
    let totalReviewed: Int
    let newCardsTodayRemaining: Int
    let reviewsTodayRemaining: Int
    let activityByDay: [DailyActivity]  // last 365 days (for heatmap)
    let reviewsByDay: [DailyActivity]   // last 30 days (for bar chart)
}

final class StatsService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Snapshot

    func snapshot(
        deckIDs: Set<UUID>?,
        settings: AppSettings
    ) throws -> StatsSnapshot {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        // Due today
        let dueToday = try countDueCards(deckIDs: deckIDs, before: now)

        // Total cards
        let totalCards = try countCards(deckIDs: deckIDs)

        // Reviews today
        let reviewedToday = try countReviewsOn(date: todayStart, deckIDs: deckIDs)
        let newTodayCount = try countNewCardsOn(date: todayStart, deckIDs: deckIDs)

        let newRemaining = max(0, settings.dailyNewCardLimit - newTodayCount)
        let reviewsRemaining = max(0, settings.dailyReviewLimit - reviewedToday)

        // Retention (30-day rolling)
        let retention = try retentionRate(deckIDs: deckIDs, days: 30)

        // Activity for heatmap (365 days)
        let activityByDay = try activityData(deckIDs: deckIDs, days: 365)

        // Reviews per day for bar chart (30 days)
        let reviewsByDay = Array(activityByDay.suffix(30))

        // Total reviewed all time
        let totalReviewed = try countAllReviews(deckIDs: deckIDs)

        return StatsSnapshot(
            retentionRate: retention,
            currentStreak: settings.streakCurrentDays,
            dueToday: dueToday,
            totalCards: totalCards,
            totalReviewed: totalReviewed,
            newCardsTodayRemaining: newRemaining,
            reviewsTodayRemaining: reviewsRemaining,
            activityByDay: activityByDay,
            reviewsByDay: reviewsByDay
        )
    }

    // MARK: - Individual queries

    func countDueCards(deckIDs: Set<UUID>?, before date: Date) throws -> Int {
        var descriptor = FetchDescriptor<OboerCard>(
            predicate: #Predicate { card in
                card.fsrsDue <= date && !card.isSuspended
            }
        )
        descriptor.fetchLimit = nil
        let cards = try modelContext.fetch(descriptor)
        if let ids = deckIDs {
            return cards.filter { card in
                guard let deck = card.deck else { return false }
                return ids.contains(deck.id)
            }.count
        }
        return cards.count
    }

    func countCards(deckIDs: Set<UUID>?) throws -> Int {
        let cards = try modelContext.fetch(FetchDescriptor<OboerCard>())
        if let ids = deckIDs {
            return cards.filter { card in
                guard let deck = card.deck else { return false }
                return ids.contains(deck.id)
            }.count
        }
        return cards.count
    }

    func retentionRate(deckIDs: Set<UUID>?, days: Int) throws -> Double {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var descriptor = FetchDescriptor<OboerReviewLog>(
            predicate: #Predicate { log in log.reviewedAt >= cutoff }
        )
        descriptor.sortBy = [SortDescriptor(\.reviewedAt)]
        let logs = try modelContext.fetch(descriptor)
        let filtered: [OboerReviewLog]
        if let ids = deckIDs {
            filtered = logs.filter { log in
                guard let deck = log.deck else { return false }
                return ids.contains(deck.id)
            }
        } else {
            filtered = logs
        }
        guard !filtered.isEmpty else { return 1.0 }
        let successful = filtered.filter { $0.wasSuccessful }.count
        return Double(successful) / Double(filtered.count)
    }

    func activityData(deckIDs: Set<UUID>?, days: Int) throws -> [DailyActivity] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = FetchDescriptor<OboerReviewLog>(
            predicate: #Predicate { log in log.reviewedAt >= cutoff }
        )
        let logs = try modelContext.fetch(descriptor)
        let filtered: [OboerReviewLog]
        if let ids = deckIDs {
            filtered = logs.filter { log in
                guard let deck = log.deck else { return false }
                return ids.contains(deck.id)
            }
        } else {
            filtered = logs
        }

        // Group by calendar day
        let calendar = Calendar.current
        var byDay: [Date: [OboerReviewLog]] = [:]
        for log in filtered {
            let day = calendar.startOfDay(for: log.reviewedAt)
            byDay[day, default: []].append(log)
        }

        // Build activity for every day in the range (fill zeros for missing days)
        var result: [DailyActivity] = []
        for offset in stride(from: -days + 1, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) else { continue }
            let dayLogs = byDay[day] ?? []
            let newCount = dayLogs.filter { $0.stateBefore == OboerCardState.new.rawValue }.count
            let total = dayLogs.count
            let successful = dayLogs.filter { $0.wasSuccessful }.count
            let retention = total > 0 ? Double(successful) / Double(total) : 1.0
            result.append(DailyActivity(date: day, reviewed: total, newCards: newCount, retentionRate: retention))
        }
        return result
    }

    // MARK: - Private helpers

    private func countReviewsOn(date: Date, deckIDs: Set<UUID>?) throws -> Int {
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let descriptor = FetchDescriptor<OboerReviewLog>(
            predicate: #Predicate { log in log.reviewedAt >= date && log.reviewedAt < endOfDay }
        )
        let logs = try modelContext.fetch(descriptor)
        if let ids = deckIDs {
            return logs.filter { log in
                guard let deck = log.deck else { return false }
                return ids.contains(deck.id)
            }.count
        }
        return logs.count
    }

    private func countNewCardsOn(date: Date, deckIDs: Set<UUID>?) throws -> Int {
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let newStateRaw = OboerCardState.new.rawValue
        let descriptor = FetchDescriptor<OboerReviewLog>(
            predicate: #Predicate { log in
                log.reviewedAt >= date &&
                log.reviewedAt < endOfDay &&
                log.stateBefore == newStateRaw
            }
        )
        let logs = try modelContext.fetch(descriptor)
        if let ids = deckIDs {
            return logs.filter { log in
                guard let deck = log.deck else { return false }
                return ids.contains(deck.id)
            }.count
        }
        return logs.count
    }

    private func countAllReviews(deckIDs: Set<UUID>?) throws -> Int {
        let logs = try modelContext.fetch(FetchDescriptor<OboerReviewLog>())
        if let ids = deckIDs {
            return logs.filter { log in
                guard let deck = log.deck else { return false }
                return ids.contains(deck.id)
            }.count
        }
        return logs.count
    }
}

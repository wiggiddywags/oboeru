import Foundation
import SwiftData

@Model
final class AppSettings {
    var dailyNewCardLimit: Int
    var dailyReviewLimit: Int
    var interleavingEnabled: Bool
    var interleavingBlockSize: Int
    var streakCurrentDays: Int
    var streakLastStudyDate: Date?

    init() {
        self.dailyNewCardLimit = 20
        self.dailyReviewLimit = 200
        self.interleavingEnabled = true
        self.interleavingBlockSize = 7
        self.streakCurrentDays = 0
        self.streakLastStudyDate = nil
    }
}

// MARK: - Fetch or create singleton

extension AppSettings {
    /// Returns the persisted settings, or inserts defaults if none exist.
    static func fetchOrCreate(in context: ModelContext) -> AppSettings {
        let descriptor = FetchDescriptor<AppSettings>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let settings = AppSettings()
        context.insert(settings)
        try? context.save()
        return settings
    }

    /// Updates the streak based on today's date.
    func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = streakLastStudyDate {
            let lastDay = Calendar.current.startOfDay(for: last)
            let diff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                streakCurrentDays += 1
            } else if diff > 1 {
                streakCurrentDays = 1
            }
            // diff == 0 means already updated today — do nothing
        } else {
            streakCurrentDays = 1
        }
        streakLastStudyDate = today
    }
}

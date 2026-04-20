import Foundation

// Native FSRS-5 implementation.
// Formulas mirror open-spaced-repetition/swift-fsrs exactly (FSRSAlgorithm.swift +
// BasicScheduler.swift from that package), avoiding its broken internal-only access.
//
// Reference: https://github.com/open-spaced-repetition/fsrs4anki/wiki/The-Algorithm

// MARK: - Preview types

struct FSRSPreview {
    let rating: OboerRating
    let nextDue: Date
    let scheduledDays: Double       // 0 = same-day (minutes)
    let nextStability: Double
    let nextDifficulty: Double
    let nextStateRaw: Int

    var intervalLabel: String {
        if scheduledDays < 1.0 / (24 * 60) {
            return "< 1 min"
        } else if scheduledDays < 1.0 / 24 {
            let mins = max(1, Int((scheduledDays * 24 * 60).rounded()))
            return "\(mins) min"
        } else if scheduledDays < 1 {
            let hrs = max(1, Int((scheduledDays * 24).rounded()))
            return "\(hrs) hr"
        } else if scheduledDays < 30 {
            let d = max(1, Int(scheduledDays.rounded()))
            return d == 1 ? "1 day" : "\(d) days"
        } else if scheduledDays < 365 {
            let m = max(1, Int((scheduledDays / 30).rounded()))
            return m == 1 ? "1 mo" : "\(m) mo"
        } else {
            let y = max(1, Int((scheduledDays / 365).rounded()))
            return y == 1 ? "1 yr" : "\(y) yr"
        }
    }
}

struct FSRSPreviews {
    let again: FSRSPreview
    let hard:  FSRSPreview
    let good:  FSRSPreview
    let easy:  FSRSPreview

    subscript(rating: OboerRating) -> FSRSPreview {
        switch rating {
        case .again: again
        case .hard:  hard
        case .good:  good
        case .easy:  easy
        }
    }
}

// MARK: - FSRS-5 Scheduler

final class FSRSService {

    // FSRS-5 default weights (19 parameters)
    static let defaultW: [Double] = [
        0.4072, 1.1829, 3.1262, 15.4722, 7.2102, 0.5316, 1.0651, 0.0234,
        1.616,  0.1544, 1.0824, 1.9813,  0.0953, 0.2975, 2.2042, 0.2407,
        2.9466, 0.5034, 0.6567
    ]

    private static let DECAY:  Double = -0.5
    private static let FACTOR: Double = 19.0 / 81.0   // = pow(0.9, 1/DECAY) - 1

    // MARK: - Public API

    /// Returns previews for all four ratings without mutating the card.
    func previewRatings(for card: OboerCard, deck: Deck, now: Date = Date()) -> FSRSPreviews {
        let w  = FSRSService.defaultW
        let rr = deck.fsrsRequestRetention
        let maxIvl = deck.fsrsMaxInterval

        let state = OboerCardState(rawValue: card.fsrsStateRaw) ?? .new

        func preview(_ rating: OboerRating) -> FSRSPreview {
            computeNext(card: card, rating: rating, state: state,
                        w: w, requestRetention: rr, maximumInterval: maxIvl, now: now)
        }

        return FSRSPreviews(
            again: preview(.again),
            hard:  preview(.hard),
            good:  preview(.good),
            easy:  preview(.easy)
        )
    }

    /// Applies a rating to the OboerCard (mutates in place) and returns a log entry.
    @discardableResult
    func applyRating(
        to card: OboerCard,
        rating: OboerRating,
        deck: Deck,
        now: Date = Date(),
        durationMs: Int = 0
    ) -> OboerReviewLog {
        let w  = FSRSService.defaultW
        let rr = deck.fsrsRequestRetention
        let maxIvl = deck.fsrsMaxInterval
        let state  = OboerCardState(rawValue: card.fsrsStateRaw) ?? .new
        let stateBefore = card.fsrsStateRaw

        let p = computeNext(card: card, rating: rating, state: state,
                            w: w, requestRetention: rr, maximumInterval: maxIvl, now: now)

        card.fsrsDue           = p.nextDue
        card.fsrsStability     = p.nextStability
        card.fsrsDifficulty    = p.nextDifficulty
        card.fsrsScheduledDays = p.scheduledDays
        card.fsrsElapsedDays   = elapsedDays(card: card, now: now)
        card.fsrsReps         += 1
        if rating == .again { card.fsrsLapses += 1 }
        card.fsrsStateRaw      = p.nextStateRaw
        card.fsrsLastReview    = now
        card.updatedAt         = now

        return OboerReviewLog(
            card: card,
            rating: rating.rawValue,
            stateBefore: stateBefore,
            stateAfter: p.nextStateRaw,
            scheduledDays: p.scheduledDays,
            elapsedDays: elapsedDays(card: card, now: now),
            stability: p.nextStability,
            difficulty: p.nextDifficulty,
            durationMs: durationMs
        )
    }

    /// Estimated probability of recall (0–1).
    func retrievability(for card: OboerCard, now: Date = Date()) -> Double {
        guard card.fsrsStability > 0 else { return 0 }
        let elapsed = elapsedDays(card: card, now: now)
        return forgettingCurve(elapsedDays: elapsed, stability: card.fsrsStability)
    }

    // MARK: - Core FSRS-5 formulas

    private func computeNext(
        card: OboerCard,
        rating: OboerRating,
        state: OboerCardState,
        w: [Double],
        requestRetention: Double,
        maximumInterval: Double,
        now: Date
    ) -> FSRSPreview {
        let elapsed = elapsedDays(card: card, now: now)
        let lastS = card.fsrsStability
        let lastD = card.fsrsDifficulty

        switch state {
        case .new:
            return newStatePreview(rating: rating, w: w, requestRetention: requestRetention, maximumInterval: maximumInterval, now: now)

        case .learning, .relearning:
            return learningStatePreview(rating: rating, lastS: lastS, lastD: lastD, elapsed: elapsed, w: w, requestRetention: requestRetention, maximumInterval: maximumInterval, now: now, currentState: state)

        case .review:
            return reviewStatePreview(rating: rating, lastS: lastS, lastD: lastD, elapsed: elapsed, w: w, requestRetention: requestRetention, maximumInterval: maximumInterval, now: now)
        }
    }

    // New card
    private func newStatePreview(
        rating: OboerRating, w: [Double],
        requestRetention: Double, maximumInterval: Double, now: Date
    ) -> FSRSPreview {
        let s = max(0.1, w[rating.rawValue - 1])
        let d = constrainDifficulty(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1)

        switch rating {
        case .again:
            let due = addMinutes(1, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 1.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.learning.rawValue)
        case .hard:
            let due = addMinutes(5, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 5.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.learning.rawValue)
        case .good:
            let due = addMinutes(10, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 10.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.learning.rawValue)
        case .easy:
            let ivl = nextInterval(s: s, elapsedDays: 0, requestRetention: requestRetention, maximumInterval: maximumInterval)
            let due = addDays(ivl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(ivl),
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.review.rawValue)
        }
    }

    // Learning / Relearning card (short-term scheduler)
    private func learningStatePreview(
        rating: OboerRating, lastS: Double, lastD: Double, elapsed: Double,
        w: [Double], requestRetention: Double, maximumInterval: Double, now: Date,
        currentState: OboerCardState
    ) -> FSRSPreview {
        let s = nextShortTermStability(s: lastS, rating: rating, w: w)
        let d = constrainDifficulty(nextDifficultyRaw(d: lastD, rating: rating, w: w))

        switch rating {
        case .again:
            let due = addMinutes(5, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 5.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: currentState.rawValue)
        case .hard:
            let due = addMinutes(10, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 10.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: currentState.rawValue)
        case .good:
            let ivl = nextInterval(s: s, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval)
            let due = addDays(ivl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(ivl),
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.review.rawValue)
        case .easy:
            let goodS = nextShortTermStability(s: lastS, rating: .good, w: w)
            let goodIvl = nextInterval(s: goodS, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval)
            let easyIvl = max(nextInterval(s: s, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval), goodIvl + 1)
            let due = addDays(easyIvl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(easyIvl),
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.review.rawValue)
        }
    }

    // Review card
    private func reviewStatePreview(
        rating: OboerRating, lastS: Double, lastD: Double, elapsed: Double,
        w: [Double], requestRetention: Double, maximumInterval: Double, now: Date
    ) -> FSRSPreview {
        let r = forgettingCurve(elapsedDays: elapsed, stability: lastS)

        switch rating {
        case .again:
            let s = clamp(w[11] * pow(lastD, -w[12]) * (pow(lastS + 1, w[13]) - 1) * exp((1 - r) * w[14]), lo: 0.01, hi: 36500)
            let d = constrainDifficulty(nextDifficultyRaw(d: lastD, rating: rating, w: w))
            let due = addMinutes(5, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: 5.0/1440,
                               nextStability: s, nextDifficulty: d, nextStateRaw: OboerCardState.relearning.rawValue)

        case .hard:
            let sHard = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1) * w[15]), lo: 0.01, hi: 36500)
            let sGood = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1)), lo: 0.01, hi: 36500)
            let dHard = constrainDifficulty(nextDifficultyRaw(d: lastD, rating: .hard, w: w))
            let hardIvl = min(nextInterval(s: sHard, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval),
                              nextInterval(s: sGood, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval))
            let due = addDays(hardIvl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(hardIvl),
                               nextStability: sHard, nextDifficulty: dHard, nextStateRaw: OboerCardState.review.rawValue)

        case .good:
            let sGood = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1)), lo: 0.01, hi: 36500)
            let sHard = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1) * w[15]), lo: 0.01, hi: 36500)
            let dGood = constrainDifficulty(nextDifficultyRaw(d: lastD, rating: .good, w: w))
            let hardIvl = nextInterval(s: sHard, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval)
            let goodIvl = max(nextInterval(s: sGood, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval), hardIvl + 1)
            let due = addDays(goodIvl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(goodIvl),
                               nextStability: sGood, nextDifficulty: dGood, nextStateRaw: OboerCardState.review.rawValue)

        case .easy:
            let sEasy = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1) * w[16]), lo: 0.01, hi: 36500)
            let sGood = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1)), lo: 0.01, hi: 36500)
            let sHard = clamp(lastS * (1 + exp(w[8]) * (11 - lastD) * pow(lastS, -w[9]) * (exp((1-r)*w[10]) - 1) * w[15]), lo: 0.01, hi: 36500)
            let dEasy = constrainDifficulty(nextDifficultyRaw(d: lastD, rating: .easy, w: w))
            let hardIvl = nextInterval(s: sHard, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval)
            let goodIvl = max(nextInterval(s: sGood, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval), hardIvl + 1)
            let easyIvl = max(nextInterval(s: sEasy, elapsedDays: elapsed, requestRetention: requestRetention, maximumInterval: maximumInterval), goodIvl + 1)
            let due = addDays(easyIvl, to: now)
            return FSRSPreview(rating: rating, nextDue: due, scheduledDays: Double(easyIvl),
                               nextStability: sEasy, nextDifficulty: dEasy, nextStateRaw: OboerCardState.review.rawValue)
        }
    }

    // MARK: - Formula helpers

    private func forgettingCurve(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.FACTOR * elapsedDays / stability, Self.DECAY)
    }

    private func nextInterval(s: Double, elapsedDays: Double, requestRetention: Double, maximumInterval: Double) -> Int {
        let modifier = (pow(requestRetention, 1.0 / Self.DECAY) - 1.0) / Self.FACTOR
        let ivl = max(1.0, min((s * modifier).rounded(), maximumInterval))
        return Int(ivl)
    }

    private func nextShortTermStability(s: Double, rating: OboerRating, w: [Double]) -> Double {
        clamp(s * exp(w[17] * (Double(rating.rawValue) - 3 + w[18])), lo: 0.01, hi: 36500)
    }

    private func nextDifficultyRaw(d: Double, rating: OboerRating, w: [Double]) -> Double {
        let initD4 = w[4] - exp(w[5] * 3.0) + 1   // D0(easy)
        let nextD   = d - w[6] * Double(rating.rawValue - 3)
        return w[7] * initD4 + (1 - w[7]) * nextD
    }

    private func constrainDifficulty(_ d: Double) -> Double {
        min(max(d, 1.0), 10.0)
    }

    private func clamp(_ v: Double, lo: Double, hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    private func elapsedDays(card: OboerCard, now: Date) -> Double {
        guard let lastReview = card.fsrsLastReview else { return 0 }
        return max(0, now.timeIntervalSince(lastReview) / 86400)
    }

    private func addMinutes(_ minutes: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: date) ?? date
    }

    private func addDays(_ days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}

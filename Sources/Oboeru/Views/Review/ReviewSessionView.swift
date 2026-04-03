import SwiftUI
import FSRS

struct ReviewSessionView: View {

    @Bindable var session: StudySession
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressHeader

            Divider()

            // Card area
            switch session.phase {
            case .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .front:
                if let card = session.currentCard {
                    CardFrontView(card: card, onShowAnswer: session.showAnswer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }

            case .back(let previews):
                if let card = session.currentCard {
                    VStack(spacing: 0) {
                        CardBackView(card: card)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        RatingBarView(previews: previews) { rating in
                            session.rate(rating)
                        }
                    }
                    .transition(.opacity)
                }

            case .finished(let summary):
                SessionSummaryView(summary: summary, onDismiss: onFinished)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: session.phase)
        .onAppear { session.start() }
        .navigationTitle(session.decks.count == 1 ? session.decks[0].name : "Study All")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("End Session") { onFinished() }
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            ProgressView(value: session.progress)
                .tint(.accentColor)
                .padding(.horizontal, 16)

            Text("\(Int(session.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Summary

struct SessionSummaryView: View {

    let summary: StudySession.SessionSummary
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Session Complete!")
                .font(.title)
                .fontWeight(.bold)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    statLabel("Reviewed", value: "\(summary.totalReviewed)")
                    statLabel("New cards", value: "\(summary.newCardsStudied)")
                }
                GridRow {
                    statLabel("Again", value: "\(summary.againCount)", color: .red)
                    statLabel("Hard", value: "\(summary.hardCount)", color: .orange)
                }
                GridRow {
                    statLabel("Good", value: "\(summary.goodCount)", color: .green)
                    statLabel("Easy", value: "\(summary.easyCount)", color: .blue)
                }
                GridRow {
                    statLabel("Duration", value: formattedDuration)
                }
            }
            .padding(24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(40)
    }

    private func statLabel(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    private var formattedDuration: String {
        let mins = Int(summary.duration / 60)
        let secs = Int(summary.duration) % 60
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }
}

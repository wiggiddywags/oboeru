import SwiftUI
import SwiftData

struct ReviewSessionView: View {

    @Bindable var session: StudySession
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingCard      = false
    @State private var answerInputEnabled = false
    @State private var typedAnswer        = ""

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            cardArea
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .onAppear { session.start() }
        .navigationTitle(session.decks.count == 1 ? session.decks[0].name : "Study All")
        .toolbar {
            // Answer input toggle
            ToolbarItem(placement: .automatic) {
                Button {
                    answerInputEnabled.toggle()
                } label: {
                    Image(systemName: answerInputEnabled ? "keyboard.fill" : "keyboard")
                }
                .help(answerInputEnabled ? "Hide answer input" : "Show answer input")
            }

            // Edit current card
            ToolbarItem(placement: .automatic) {
                Button {
                    isEditingCard = true
                } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit this card")
                .disabled(session.currentCard == nil)
            }

            // End session
            ToolbarItem(placement: .automatic) {
                Button("End Session") { onFinished() }
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isEditingCard) {
            if let card = session.currentCard, let deck = card.deck {
                CardEditorSheet(
                    existingCard: card,
                    deck: deck,
                    modelContext: modelContext,
                    onDismiss: { isEditingCard = false }
                )
            }
        }
    }

    // MARK: - Card area

    @ViewBuilder
    private var cardArea: some View {
        switch session.phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .front:
            if let card = session.currentCard {
                CardFrontView(
                    card: card,
                    typedAnswer: $typedAnswer,
                    answerInputEnabled: answerInputEnabled,
                    onShowAnswer: session.showAnswer
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(card.id)
            }

        case .back(let previews):
            if let card = session.currentCard {
                VStack(spacing: 0) {
                    CardBackView(card: card, typedAnswer: typedAnswer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    RatingBarView(previews: previews) { rating in
                        typedAnswer = ""
                        session.rate(rating)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity
                ))
            }

        case .finished(let summary):
            SessionSummaryView(summary: summary, onDismiss: onFinished)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    // MARK: - Progress header

    private var deckColor: Color {
        if session.decks.count == 1 {
            return Color(hex: session.decks[0].colorHex) ?? .accentColor
        }
        return .accentColor
    }

    private var progressHeader: some View {
        HStack(spacing: 12) {
            // Remaining card counts derived from remainingCount + progress
            let done = Int((session.progress * Double(session.remainingCount + 1)).rounded())
            Text("\(session.remainingCount) left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(deckColor)
                        .frame(width: geo.size.width * session.progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: session.progress)
                }
            }
            .frame(height: 6)

            Text("\(Int(session.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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

            Text("Session Complete")
                .font(.custom("Georgia", size: 28))
                .fontWeight(.semibold)

            Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 14) {
                GridRow {
                    statLabel("Reviewed",  value: "\(summary.totalReviewed)")
                    statLabel("New cards", value: "\(summary.newCardsStudied)")
                }
                GridRow {
                    statLabel("Again", value: "\(summary.againCount)", color: .red)
                    statLabel("Hard",  value: "\(summary.hardCount)",  color: .orange)
                }
                GridRow {
                    statLabel("Good", value: "\(summary.goodCount)", color: .green)
                    statLabel("Easy", value: "\(summary.easyCount)", color: .blue)
                }
                GridRow {
                    statLabel("Duration", value: formattedDuration)
                }
            }
            .padding(28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))

            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(48)
    }

    private func statLabel(_ label: String, value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.custom("Georgia", size: 20))
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }

    private var formattedDuration: String {
        let mins = Int(summary.duration / 60)
        let secs = Int(summary.duration) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }
}

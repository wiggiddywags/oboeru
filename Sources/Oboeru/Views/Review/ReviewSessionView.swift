import SwiftUI
import SwiftData

// MARK: - Card theme

enum CardTheme: String, CaseIterable {
    case auto   = "auto"
    case light  = "light"
    case sepia  = "sepia"
    case dark   = "dark"

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .auto:  return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .sepia: return "leaf"
        case .dark:  return "moon"
        }
    }

    func backgroundColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .auto:  return Color(nsColor: .textBackgroundColor)
        case .light: return Color.white
        case .sepia: return Color(red: 1.0, green: 0.97, blue: 0.90)
        case .dark:  return Color(red: 0.14, green: 0.14, blue: 0.16)
        }
    }

    func foregroundColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .dark:  return .white
        default:     return Color(nsColor: .labelColor)
        }
    }
}

// MARK: - ReviewSessionView

struct ReviewSessionView: View {

    @Bindable var session: StudySession
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("oboer.cardTheme") private var cardThemeRaw: String = CardTheme.auto.rawValue

    @State private var isEditingCard      = false
    @State private var answerInputEnabled = false
    @State private var typedAnswer        = ""
    @State private var showThemePicker    = false

    private var cardTheme: CardTheme {
        CardTheme(rawValue: cardThemeRaw) ?? .auto
    }

    private var cardBackground: Color {
        cardTheme.backgroundColor(for: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            cardArea
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .onAppear { session.start() }
        .navigationTitle(sessionTitle)
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

            // Card theme picker
            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(CardTheme.allCases, id: \.rawValue) { theme in
                        Button {
                            cardThemeRaw = theme.rawValue
                        } label: {
                            Label(theme.label, systemImage: theme.icon)
                        }
                    }
                } label: {
                    Image(systemName: cardTheme.icon)
                }
                .help("Card theme")
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

    // MARK: - Session title

    private var sessionTitle: String {
        if session.decks.count == 1 {
            return session.decks[0].name
        }
        // Check if studying a parent + sub-decks
        let names = session.decks.map(\.name)
        return names.count <= 2 ? names.joined(separator: " + ") : "Study All"
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
                ScrollView {
                    VStack {
                        Spacer(minLength: 28)
                        cardFrontContainer(card: card)
                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .id(card.id)
            }

        case .back(let previews):
            if let card = session.currentCard {
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 28)
                        cardBackContainer(card: card)
                        ratingContainer(previews: previews)
                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
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

    // MARK: - Physical card containers

    private func cardFrontContainer(card: OboerCard) -> some View {
        VStack(spacing: 0) {
            CardFrontView(
                card: card,
                typedAnswer: $typedAnswer,
                answerInputEnabled: answerInputEnabled,
                onShowAnswer: session.showAnswer
            )
        }
        .frame(maxWidth: 580)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .cardShadow()
        .padding(.horizontal, 32)
    }

    private func cardBackContainer(card: OboerCard) -> some View {
        CardBackView(card: card, typedAnswer: typedAnswer)
            .frame(maxWidth: 580)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
            .cardShadow()
            .padding(.horizontal, 32)
    }

    private func ratingContainer(previews: FSRSPreviews) -> some View {
        RatingBarView(previews: previews) { rating in
            typedAnswer = ""
            session.rate(rating)
        }
        .frame(maxWidth: 580)
        .background(.bar, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .cardShadow(opacity: 0.04)
        .padding(.horizontal, 32)
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
            Text("\(session.remainingCount) left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

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

// MARK: - Card shadow modifier

private extension View {
    func cardShadow(opacity: Double = 1.0) -> some View {
        self
            .shadow(color: .black.opacity(0.09 * opacity), radius: 2, x: 0, y: 1)
            .shadow(color: .black.opacity(0.06 * opacity), radius: 10, x: 0, y: 5)
            .shadow(color: .black.opacity(0.03 * opacity), radius: 28, x: 0, y: 14)
    }
}

// MARK: - Session summary

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

import SwiftUI
import SwiftData

struct CardListView: View {

    @State private var vm: DeckDetailViewModel
    @State private var isShowingImportSheet = false
    @State private var viewMode: ViewMode = .list
    @Environment(\.modelContext) private var modelContext

    let onStudy: () -> Void

    enum ViewMode { case list, grid }

    init(deck: Deck, modelContext: ModelContext, onStudy: @escaping () -> Void) {
        _vm = State(initialValue: DeckDetailViewModel(deck: deck, modelContext: modelContext))
        self.onStudy = onStudy
    }

    var body: some View {
        VStack(spacing: 0) {
            deckHeader
            Divider()
            cardToolbar
            Divider()
            cardList
        }
        .sheet(isPresented: $vm.isShowingCardEditor) { vm.load() } content: {
            CardEditorSheet(
                existingCard: vm.editingCard,
                deck: vm.deck,
                modelContext: modelContext,
                onDismiss: {
                    vm.isShowingCardEditor = false
                    vm.load()
                }
            )
        }
        .sheet(isPresented: $isShowingImportSheet) { vm.load() } content: {
            ImportSheetView(
                deck: vm.deck,
                modelContext: modelContext,
                onDismiss: {
                    isShowingImportSheet = false
                    vm.load()
                }
            )
        }
        .onAppear { vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .newCardRequested)) { _ in
            vm.newCardForEditing()
        }
    }

    // MARK: - Deck header

    private var deckHeader: some View {
        let color = Color(hex: vm.deck.colorHex) ?? .accentColor
        let due   = vm.cards.filter { $0.isDue && !$0.isSuspended }.count
        let new   = vm.cards.filter { $0.fsrsState == .new }.count

        return HStack(spacing: 16) {

            // Icon
            Image(systemName: vm.deck.iconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            // Name + stats
            VStack(alignment: .leading, spacing: 5) {
                Text(vm.deck.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    statPill("\(vm.cards.count) cards", color: .secondary)
                    if due > 0 {
                        statPill("\(due) due", color: .green)
                    }
                    if new > 0 {
                        statPill("\(new) new", color: .blue)
                    }
                }
            }

            Spacer()

            // Study button
            Button(action: onStudy) {
                Label(
                    due > 0 ? "Study  \(due)" : "Study",
                    systemImage: "play.fill"
                )
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(color)
            .disabled(vm.cards.isEmpty)
            .help("Start a review session for this deck")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(color.opacity(0.05))
    }

    private func statPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Card toolbar (search, filter, actions)

    private var cardToolbar: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Search cards…", text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)

            // Filter
            Picker("", selection: $vm.filterState) {
                ForEach(DeckDetailViewModel.FilterState.allCases, id: \.self) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .labelsHidden()

            Spacer()

            // View mode toggle
            Picker("View", selection: $viewMode) {
                Image(systemName: "list.bullet").tag(ViewMode.list)
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .labelsHidden()
            .help("Switch between list and grid view")

            // Import
            Button {
                isShowingImportSheet = true
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .help("Import cards from CSV or Anki")

            // New card
            Button {
                vm.newCardForEditing()
            } label: {
                Label("New Card", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Card list

    private var cardList: some View {
        let cards = vm.filteredCards()
        let color = Color(hex: vm.deck.colorHex) ?? .accentColor
        return Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    vm.searchText.isEmpty ? "No Cards" : "No Results",
                    systemImage: vm.searchText.isEmpty ? "rectangle.stack.badge.plus" : "magnifyingglass",
                    description: Text(vm.searchText.isEmpty
                        ? "Tap New Card to add your first card."
                        : "Try a different search term.")
                )
            } else if viewMode == .list {
                List {
                    ForEach(cards) { card in
                        CardRowView(card: card)
                            .contextMenu { cardContextMenu(for: card) }
                            .onTapGesture(count: 2) {
                                vm.editingCard = card
                                vm.isShowingCardEditor = true
                            }
                    }
                }
                .listStyle(.inset)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(cards) { card in
                            IndexCardCell(card: card, accentColor: color)
                                .contextMenu { cardContextMenu(for: card) }
                                .onTapGesture(count: 2) {
                                    vm.editingCard = card
                                    vm.isShowingCardEditor = true
                                }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func cardContextMenu(for card: OboerCard) -> some View {
        Button("Edit") {
            vm.editingCard = card
            vm.isShowingCardEditor = true
        }
        Button(card.isSuspended ? "Unsuspend" : "Suspend") {
            vm.suspendCard(card, suspended: !card.isSuspended)
        }
        Button("Reset Schedule") {
            vm.resetCardSchedule(card)
        }
        Divider()
        Button("Delete", role: .destructive) {
            vm.deleteCard(card)
        }
    }
}

// MARK: - Card row

private struct CardRowView: View {

    let card: OboerCard

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: card.cardType == .cloze ? "text.word.spacing" : "rectangle.2.swap")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayFront)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(card.isSuspended ? .secondary : .primary)

                if card.cardType == .basic && !card.backText.isEmpty {
                    Text(card.backText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
            stateBadge
        }
        .opacity(card.isSuspended ? 0.5 : 1)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch card.fsrsState {
        case .new:
            badge("New", color: .blue)
        case .learning, .relearning:
            badge("Learning", color: .orange)
        case .review:
            if card.isDue {
                badge("Due", color: .green)
            } else {
                Text(card.fsrsDue, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Index card cell (grid view)

private struct IndexCardCell: View {

    let card: OboerCard
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Accent stripe
            accentColor
                .frame(maxWidth: .infinity)
                .frame(height: 4)

            VStack(alignment: .leading, spacing: 8) {

                // Type icon + state badge
                HStack {
                    Image(systemName: card.cardType == .cloze ? "text.word.spacing" : "rectangle.2.swap")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    stateBadge
                }

                // Front text
                Text(card.displayFront)
                    .font(.callout)
                    .lineLimit(4)
                    .foregroundStyle(card.isSuspended ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if card.cardType == .basic && !card.backText.isEmpty {
                    Divider()
                    Text(card.backText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .opacity(card.isSuspended ? 0.5 : 1)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch card.fsrsState {
        case .new:
            badge("New", color: .blue)
        case .learning, .relearning:
            badge("Learning", color: .orange)
        case .review:
            if card.isDue {
                badge("Due", color: .green)
            } else {
                Text(card.fsrsDue, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

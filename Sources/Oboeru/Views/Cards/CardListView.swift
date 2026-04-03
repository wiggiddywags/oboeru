import SwiftUI
import SwiftData

struct CardListView: View {

    @State private var vm: DeckDetailViewModel
    @Environment(\.modelContext) private var modelContext

    init(deck: Deck, modelContext: ModelContext) {
        _vm = State(initialValue: DeckDetailViewModel(deck: deck, modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            cardList
        }
        .navigationTitle(vm.deck.name)
        .sheet(isPresented: $vm.isShowingCardEditor) {
            vm.load()
        } content: {
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
        .onAppear { vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .newCardRequested)) { _ in
            vm.newCardForEditing()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cards…", text: $vm.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 280)

            // Filter
            Picker("Filter", selection: $vm.filterState) {
                ForEach(DeckDetailViewModel.FilterState.allCases, id: \.self) { state in
                    Text(state.rawValue).tag(state)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)

            Spacer()

            // Add card button
            Button {
                vm.newCardForEditing()
            } label: {
                Label("New Card", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var cardList: some View {
        let cards = vm.filteredCards()
        return Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    vm.searchText.isEmpty ? "No Cards" : "No Results",
                    systemImage: vm.searchText.isEmpty ? "rectangle.stack.badge.plus" : "magnifyingglass",
                    description: Text(vm.searchText.isEmpty ? "Add your first card to get started." : "Try a different search term.")
                )
            } else {
                List {
                    ForEach(cards) { card in
                        CardRowView(card: card)
                            .contextMenu {
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
                            .onTapGesture(count: 2) {
                                vm.editingCard = card
                                vm.isShowingCardEditor = true
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct CardRowView: View {

    let card: OboerCard

    var body: some View {
        HStack(spacing: 12) {
            // Type indicator
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

            // State badge
            stateBadge
        }
        .opacity(card.isSuspended ? 0.5 : 1)
    }

    @ViewBuilder
    private var stateBadge: some View {
        switch card.fsrsState {
        case .new:
            Text("New")
                .font(.caption2)
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue.opacity(0.12), in: Capsule())
        case .learning, .relearning:
            Text("Learning")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.12), in: Capsule())
        case .review:
            if card.isDue {
                Text("Due")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.12), in: Capsule())
            } else {
                Text(card.fsrsDue, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

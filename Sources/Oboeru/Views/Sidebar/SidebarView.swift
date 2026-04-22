import SwiftUI

struct SidebarView: View {

    @Bindable var vm: DeckListViewModel
    var onStudy: (UUID?) -> Void   // nil = study all
    var onStats: () -> Void

    var body: some View {
        List(selection: $vm.selectedDeckID) {
            studyAllRow

            Section("Decks") {
                ForEach(vm.decks) { deck in
                    DeckRowView(
                        deck: deck,
                        dueCount: vm.dueCounts[deck.id] ?? 0,
                        onStudy: { onStudy(deck.id) },
                        onEdit:  { vm.editingDeck = deck; vm.isShowingNewDeckSheet = true },
                        onDelete:  { vm.deleteDeck(deck) },
                        onArchive: { vm.archiveDeck(deck) }
                    )
                    .tag(deck.id)
                }
            }

            Section {
                Label("Statistics", systemImage: "chart.bar.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture { onStats() }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Oboeru")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { vm.isShowingNewDeckSheet = true } label: {
                    Image(systemName: "plus")
                }
                .help("New Deck (⇧⌘N)")
            }
        }
        .sheet(isPresented: $vm.isShowingNewDeckSheet) {
            vm.load()
        } content: {
            DeckEditorSheet(
                existingDeck: vm.editingDeck,
                onSave: { name, color, icon in
                    if let existing = vm.editingDeck {
                        vm.updateDeck(existing, name: name, colorHex: color, iconName: icon)
                    } else {
                        vm.createDeck(name: name, colorHex: color, iconName: icon)
                    }
                    vm.editingDeck           = nil
                    vm.isShowingNewDeckSheet = false
                },
                onCancel: {
                    vm.editingDeck         = nil
                    vm.isShowingNewDeckSheet = false
                }
            )
        }
        .onAppear { vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .newDeckRequested)) { _ in
            vm.isShowingNewDeckSheet = true
        }
    }

    // MARK: - Study All row

    private var studyAllRow: some View {
        let dueAll = vm.dueCounts[UUID.zero] ?? 0
        return HStack {
            Label("Study All", systemImage: "sparkles.rectangle.stack")
                .foregroundStyle(dueAll > 0 ? .primary : .secondary)
            Spacer()
            if dueAll > 0 {
                Text("\(dueAll)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onStudy(nil) }
    }
}

// MARK: - Deck row

private struct DeckRowView: View {

    let deck: Deck
    let dueCount: Int
    let onStudy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: deck.iconName)
                .foregroundStyle(Color(hex: deck.colorHex) ?? .accentColor)
                .frame(width: 18)

            Text(deck.name)
                .lineLimit(1)

            Spacer()

            if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .contextMenu {
            Button("Study Now", action: onStudy)
            Button("Edit Deck",  action: onEdit)
            Divider()
            Button("Archive",  action: onArchive)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let newDeckRequested  = Notification.Name("OboerNewDeckRequested")
    static let newCardRequested  = Notification.Name("OboerNewCardRequested")
    static let studyRequested    = Notification.Name("OboerStudyRequested")
    static let studyAllRequested = Notification.Name("OboerStudyAllRequested")
}

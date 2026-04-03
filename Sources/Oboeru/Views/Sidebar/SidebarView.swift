import SwiftUI

struct SidebarView: View {

    @Bindable var vm: DeckListViewModel
    var onStudy: (UUID?) -> Void   // nil = study all
    var onStats: () -> Void

    var body: some View {
        List(selection: $vm.selectedDeckID) {
            // Study All row
            studyAllRow

            Section("Decks") {
                ForEach(vm.decks) { deck in
                    DeckRowView(
                        deck: deck,
                        dueCount: vm.dueCounts[deck.id] ?? 0,
                        onStudy: { onStudy(deck.id) },
                        onDelete: { vm.deleteDeck(deck) },
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
                Button {
                    vm.isShowingNewDeckSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Deck (⇧⌘N)")
            }
        }
        .sheet(isPresented: $vm.isShowingNewDeckSheet) {
            vm.load()
        } content: {
            DeckEditorSheet(onSave: { name, color, icon in
                vm.createDeck(name: name, colorHex: color, iconName: icon)
                vm.isShowingNewDeckSheet = false
            }, onCancel: {
                vm.isShowingNewDeckSheet = false
            })
        }
        .onAppear { vm.load() }
        .onReceive(
            NotificationCenter.default.publisher(for: .newDeckRequested)
        ) { _ in
            vm.isShowingNewDeckSheet = true
        }
    }

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
                    .background(.accentColor, in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onStudy(nil) }
    }
}

private struct DeckRowView: View {

    let deck: Deck
    let dueCount: Int
    let onStudy: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void

    var body: some View {
        HStack {
            Image(systemName: deck.iconName)
                .foregroundStyle(Color(hex: deck.colorHex) ?? .accentColor)
                .frame(width: 20)

            Text(deck.name)
                .lineLimit(1)

            Spacer()

            if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.accentColor, in: Capsule())
            }
        }
        .contextMenu {
            Button("Study Now", action: onStudy)
            Divider()
            Button("Archive Deck", action: onArchive)
            Button("Delete Deck", role: .destructive, action: onDelete)
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

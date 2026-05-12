import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var deckListVM: DeckListViewModel?
    @State private var activeSession: StudySession?
    @State private var showStats = true
    @State private var showLibrary = false

    var body: some View {
        Group {
            if let vm = deckListVM {
                mainSplitView(vm: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { setupVM() }
        .onReceive(NotificationCenter.default.publisher(for: .studyAllRequested)) { _ in
            startStudy(deckID: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .studyRequested)) { _ in
            startStudy(deckID: deckListVM?.selectedDeckID)
        }
    }

    private func setupVM() {
        guard deckListVM == nil else { return }
        let vm = DeckListViewModel(modelContext: modelContext)
        vm.load()
        deckListVM = vm
    }

    private func startStudy(deckID: UUID?) {
        guard let vm = deckListVM else { return }
        let settings = AppSettings.fetchOrCreate(in: modelContext)
        activeSession = vm.makeStudySession(for: deckID, settings: settings)
        showStats = false
    }

    // MARK: - Layout

    @ViewBuilder
    private func mainSplitView(vm: DeckListViewModel) -> some View {
        // Two-column split: sidebar + main area.
        // The main area switches between deck detail, review session, and stats.
        // This hides the card list the moment study begins.
        NavigationSplitView {
            SidebarView(
                vm: vm,
                onStudy: { deckID in startStudy(deckID: deckID) },
                onStats: { showStats = true; showLibrary = false; activeSession = nil },
                onLibrary: { showLibrary = true; showStats = false; activeSession = nil; vm.selectedDeckID = nil }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            mainDetailView(vm: vm)
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: vm.selectedDeckID) { _, id in
            if id != nil { showStats = false; showLibrary = false }
        }
    }

    @ViewBuilder
    private func mainDetailView(vm: DeckListViewModel) -> some View {
        if let session = activeSession {
            ReviewSessionView(session: session) {
                activeSession = nil
                vm.refreshDueCounts()
            }
        } else if showLibrary {
            LibraryView(vm: vm)
        } else if showStats {
            StatsDashboardView()
        } else if let deck = vm.selectedDeck {
            CardListView(
                deck: deck,
                subDecks: vm.subDecks(of: deck),
                modelContext: modelContext,
                onStudy: { startStudy(deckID: deck.id) }
            )
            .id(deck.id)
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Select a Deck")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Choose a deck from the sidebar to browse cards,\nor create a new deck with the + button.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

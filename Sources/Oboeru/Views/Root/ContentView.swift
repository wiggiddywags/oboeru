import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var deckListVM: DeckListViewModel?
    @State private var activeSession: StudySession?
    @State private var showStats = false

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

    @ViewBuilder
    private func mainSplitView(vm: DeckListViewModel) -> some View {
        NavigationSplitView {
            SidebarView(
                vm: vm,
                onStudy: { deckID in startStudy(deckID: deckID) },
                onStats: { showStats = true; activeSession = nil }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            if let deck = vm.selectedDeck {
                CardListView(deck: deck, modelContext: modelContext)
            } else {
                ContentUnavailableView(
                    "Select a Deck",
                    systemImage: "rectangle.stack",
                    description: Text("Choose a deck from the sidebar to browse its cards.")
                )
            }
        } detail: {
            if let session = activeSession {
                ReviewSessionView(session: session) {
                    activeSession = nil
                    vm.refreshDueCounts()
                }
            } else if showStats {
                StatsDashboardView()
            } else {
                welcomeDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var welcomeDetail: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Ready to study?")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Select a deck and tap Study, or use Study All.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

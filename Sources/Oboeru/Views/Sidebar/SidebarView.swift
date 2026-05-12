import SwiftUI
import SwiftData
import AppKit

private struct PendingCSVImport: Identifiable {
    let id = UUID()
    let deck: Deck
    let url: URL
}

struct SidebarView: View {

    @Bindable var vm: DeckListViewModel
    var onStudy: (UUID?) -> Void
    var onStats: () -> Void
    var onLibrary: () -> Void

    @Environment(\.modelContext) private var modelContext

    /// Stores UUIDs of COLLAPSED parent decks (comma-separated). Absent = expanded (default).
    @AppStorage("oboeru.collapsedDeckIDs") private var collapsedIDsRaw: String = ""

    @State private var pendingCSVImport: PendingCSVImport? = nil
    @State private var showAnkiPicker      = false
    @State private var showMarkdownPicker  = false
    @State private var showOboerPicker     = false
    @State private var pendingAnkiURL:     URL? = nil
    @State private var pendingMarkdownURL: URL? = nil
    @State private var importError: String? = nil
    @State private var showImportError     = false
    @State private var showDocumentAIImport = false
    @State private var showURLAIImport      = false

    var body: some View {
        List(selection: $vm.selectedDeckID) {
            studyAllRow

            Section("Decks") {
                ForEach(vm.topLevelDecks) { deck in
                    let children = vm.decks.filter { $0.parentDeckID == deck.id }
                    deckRow(deck, children: children)
                    if !children.isEmpty && isExpanded(deck) {
                        ForEach(children) { child in
                            deckRow(child, isChild: true, children: [])
                        }
                        .onMove { from, to in
                            vm.moveDecks(from: from, to: to, parentID: deck.id)
                        }
                    }
                }
                .onMove { from, to in
                    vm.moveDecks(from: from, to: to, parentID: nil)
                }
            }

            Section {
                HStack {
                    Label("Library", systemImage: "books.vertical.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    let available = LibraryService.allBundles.count
                    Text("\(available)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                .contentShape(Rectangle())
                .onTapGesture { onLibrary() }

                Label("Statistics", systemImage: "chart.bar.fill")
                    .foregroundStyle(.secondary)
                    .onTapGesture { onStats() }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Oboeru")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Section("Create") {
                        Button {
                            vm.isShowingNewDeckSheet = true
                        } label: {
                            Label("New Deck…", systemImage: "plus.rectangle.on.rectangle")
                        }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                    Section("Import") {
                        Button { showAnkiPicker = true } label: {
                            Label("Import Anki Deck (.apkg)…", systemImage: "arrow.down.doc")
                        }
                        Button { showMarkdownPicker = true } label: {
                            Label("Import Markdown (.md)…", systemImage: "doc.text")
                        }
                        Button { showOboerPicker = true } label: {
                            Label("Open Deck (.oboeru)…", systemImage: "square.and.arrow.down")
                        }
                    }
                    Section("AI Import") {
                        Button { showDocumentAIImport = true } label: {
                            Label("Generate from Document…", systemImage: "doc.badge.plus")
                        }
                        Button { showURLAIImport = true } label: {
                            Label("Generate from URL…", systemImage: "globe.badge.chevron.backward")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Deck / Import")
            }
        }
        // Deck editor sheet
        .sheet(isPresented: $vm.isShowingNewDeckSheet) {
            vm.load()
        } content: {
            DeckEditorSheet(
                existingDeck: vm.editingDeck,
                allDecks: vm.topLevelDecks,
                onSave: { name, color, icon, parentID, csvURL in
                    if let existing = vm.editingDeck {
                        vm.updateDeck(existing, name: name, colorHex: color, iconName: icon, parentDeckID: parentID)
                    } else {
                        let newDeck = vm.createDeck(name: name, colorHex: color, iconName: icon, parentDeckID: parentID)
                        if let url = csvURL {
                            pendingCSVImport = PendingCSVImport(deck: newDeck, url: url)
                        }
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
        // CSV
        .sheet(item: $pendingCSVImport) { pending in
            CSVImportPreviewSheet(
                deck: pending.deck,
                initialURL: pending.url,
                modelContext: modelContext,
                onDismiss: { pendingCSVImport = nil; vm.load() }
            )
        }
        // Anki import
        .fileImporter(
            isPresented: $showAnkiPicker,
            allowedContentTypes: [.init(filenameExtension: "apkg") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result { pendingAnkiURL = urls.first }
        }
        .sheet(
            isPresented: Binding(
                get: { pendingAnkiURL != nil },
                set: { if !$0 { pendingAnkiURL = nil } }
            )
        ) {
            if let url = pendingAnkiURL {
                AnkiImportPreviewSheet(url: url, modelContext: modelContext) {
                    pendingAnkiURL = nil
                    vm.load()
                }
            }
        }
        // Markdown import
        .fileImporter(
            isPresented: $showMarkdownPicker,
            allowedContentTypes: [.plainText, .init(filenameExtension: "md") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result { pendingMarkdownURL = urls.first }
        }
        .sheet(
            isPresented: Binding(
                get: { pendingMarkdownURL != nil },
                set: { if !$0 { pendingMarkdownURL = nil } }
            )
        ) {
            if let url = pendingMarkdownURL {
                MarkdownImportPreviewSheet(url: url, modelContext: modelContext) {
                    pendingMarkdownURL = nil
                    vm.load()
                }
            }
        }
        // .oboeru import
        .fileImporter(
            isPresented: $showOboerPicker,
            allowedContentTypes: [.json, .init(filenameExtension: "oboeru") ?? .json],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let pkg  = try DeckShareService.import(from: data)
                try DeckShareService.apply(package: pkg, to: modelContext)
                vm.load()
            } catch {
                importError = error.localizedDescription
                showImportError = true
            }
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? "Unknown error")
        }
        // AI: Document import
        .sheet(isPresented: $showDocumentAIImport) {
            DocumentAIImportSheet(
                allDecks: vm.decks,
                defaultDeck: vm.selectedDeck,
                modelContext: modelContext,
                onDismiss: { showDocumentAIImport = false; vm.load() }
            )
        }
        // AI: URL import
        .sheet(isPresented: $showURLAIImport) {
            URLAIImportSheet(
                allDecks: vm.decks,
                defaultDeck: vm.selectedDeck,
                modelContext: modelContext,
                onDismiss: { showURLAIImport = false; vm.load() }
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

    @ViewBuilder
    private func deckRow(_ deck: Deck, isChild: Bool = false, children: [Deck]) -> some View {
        DeckRowView(
            deck: deck,
            dueCount: vm.dueCounts[deck.id] ?? 0,
            isChild: isChild,
            hasSubDecks: !children.isEmpty,
            isExpanded: isExpanded(deck),
            onStudy: { onStudy(deck.id) },
            onEdit:  { vm.editingDeck = deck; vm.isShowingNewDeckSheet = true },
            onDelete:  { vm.deleteDeck(deck) },
            onArchive: { vm.archiveDeck(deck) },
            onExport: { exportDeck(deck) },
            onToggleExpand: { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { toggleExpanded(deck) } }
        )
        .tag(deck.id)
    }

    // MARK: - Collapse state

    private var collapsedIDs: Set<UUID> {
        Set(collapsedIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func isExpanded(_ deck: Deck) -> Bool {
        !collapsedIDs.contains(deck.id)
    }

    private func toggleExpanded(_ deck: Deck) {
        var ids = collapsedIDs
        if ids.contains(deck.id) { ids.remove(deck.id) } else { ids.insert(deck.id) }
        collapsedIDsRaw = ids.map(\.uuidString).joined(separator: ",")
    }

    private func exportDeck(_ deck: Deck) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(deck.name).oboeru"
        panel.prompt = "Export"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try DeckShareService.export(deck: deck)
                try data.write(to: url)
            } catch { /* silent */ }
        }
    }
}

// MARK: - Deck row

private struct DeckRowView: View {

    let deck: Deck
    let dueCount: Int
    let isChild: Bool
    let hasSubDecks: Bool
    let isExpanded: Bool
    let onStudy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void
    let onExport: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isChild {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }

            Image(systemName: deck.iconName)
                .foregroundStyle(Color(hex: deck.colorHex) ?? .accentColor)
                .frame(width: 18)

            Text(deck.name)
                .lineLimit(1)

            Spacer()

            if hasSubDecks {
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
            }

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
            Button("Study Now",   action: onStudy)
            Button("Edit Deck",   action: onEdit)
            Divider()
            Button("Export Deck…", action: onExport)
            Divider()
            Button("Archive",     action: onArchive)
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

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

    @Environment(\.modelContext) private var modelContext
    @State private var pendingCSVImport: PendingCSVImport? = nil
    @State private var showAnkiPicker      = false
    @State private var showMarkdownPicker  = false
    @State private var showOboerPicker     = false
    @State private var pendingAnkiURL:     URL? = nil
    @State private var pendingMarkdownURL: URL? = nil
    @State private var importError: String? = nil
    @State private var showImportError     = false

    var body: some View {
        List(selection: $vm.selectedDeckID) {
            studyAllRow

            Section("Decks") {
                ForEach(vm.topLevelDecks) { deck in
                    deckRow(deck)
                    ForEach(vm.decks.filter { $0.parentDeckID == deck.id }) { child in
                        deckRow(child, isChild: true)
                    }
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
    private func deckRow(_ deck: Deck, isChild: Bool = false) -> some View {
        let hasChildren = vm.decks.contains(where: { $0.parentDeckID == deck.id })
        DeckRowView(
            deck: deck,
            dueCount: vm.dueCounts[deck.id] ?? 0,
            isChild: isChild,
            hasSubDecks: hasChildren,
            onStudy: { onStudy(deck.id) },
            onEdit:  { vm.editingDeck = deck; vm.isShowingNewDeckSheet = true },
            onDelete:  { vm.deleteDeck(deck) },
            onArchive: { vm.archiveDeck(deck) },
            onExport: { exportDeck(deck) }
        )
        .tag(deck.id)
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
    let onStudy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onArchive: () -> Void
    let onExport: () -> Void

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

            if hasSubDecks {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

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

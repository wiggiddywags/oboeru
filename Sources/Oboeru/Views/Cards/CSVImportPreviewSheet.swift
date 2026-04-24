import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Full-featured CSV preview sheet.
/// Shows editable cards parsed from a CSV before they are committed to the deck.
/// • Invoked from the "Import" button on an existing deck (CSV path)
/// • Invoked automatically after creating a new deck with an attached CSV
struct CSVImportPreviewSheet: View {

    let deck: Deck
    var initialURL: URL? = nil        // pre-load from DeckEditorSheet flow
    let modelContext: ModelContext
    let onDismiss: () -> Void

    // MARK: - Phase

    enum Phase {
        case choosingFile
        case parsing
        case previewing
        case importing
        case done(Int)
    }

    @State private var phase: Phase = .choosingFile
    @State private var draftCards: [CSVDraftCard] = []
    @State private var parseErrors: [String] = []
    @State private var showFilePicker = false
    @State private var showErrors = false
    @State private var fileName = ""

    private var enabledCount: Int { draftCards.filter(\.isEnabled).count }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            Group {
                switch phase {
                case .choosingFile:
                    choosingFileView
                case .parsing:
                    parsingView
                case .previewing:
                    previewTable
                case .importing:
                    importingView
                case .done(let count):
                    doneView(count: count)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 820, height: 620)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                parseFile(url: url)
            }
        }
        .onAppear {
            if let url = initialURL {
                parseFile(url: url)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Cards from CSV")
                    .font(.title2).fontWeight(.semibold)
                if !fileName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                        Text(fileName)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if case .previewing = phase {
                Button("Choose Different File") {
                    showFilePicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button("Cancel", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Choose file

    private var choosingFileView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Choose a CSV File")
                    .font(.title3).fontWeight(.medium)
                Text("One card per row. Two columns for Basic cards (Front, Back),\nor a single column with {{cloze}} markers for Cloze cards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Choose File…") { showFilePicker = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                ForEach([
                    "Basic: Front, Back [, Front Image URL, Back Image URL]",
                    "Cloze: single Text column with {{gap}} markers",
                    "First row may be a header (auto-detected)",
                ], id: \.self) { line in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•").foregroundStyle(.secondary)
                        Text(line).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(48)
    }

    // MARK: - Parsing spinner

    private var parsingView: some View {
        VStack(spacing: 14) {
            ProgressView().progressViewStyle(.circular)
            Text("Parsing \(fileName)…").foregroundStyle(.secondary)
        }
    }

    // MARK: - Preview table

    private var previewTable: some View {
        VStack(spacing: 0) {

            // ── Stats / action bar ──────────────────────────────────────────
            HStack(spacing: 14) {
                Label("\(draftCards.count) cards", systemImage: "tablecells")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !parseErrors.isEmpty {
                    Button {
                        showErrors.toggle()
                    } label: {
                        Label("\(parseErrors.count) skipped", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showErrors, arrowEdge: .bottom) {
                        skippedErrorsPopover
                    }
                }

                Spacer()

                Button("Select All") {
                    for i in draftCards.indices { draftCards[i].isEnabled = true }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)

                Button("Deselect All") {
                    for i in draftCards.indices { draftCards[i].isEnabled = false }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(.bar)

            Divider()

            // ── Column headers ──────────────────────────────────────────────
            HStack(spacing: 0) {
                Color.clear.frame(width: 46)         // checkbox + type
                columnHeader("Front", flex: true)
                Divider().frame(height: 14).padding(.horizontal, 4)
                columnHeader("Back", flex: true)
                Color.clear.frame(width: 30)          // delete button
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6))

            Divider()

            // ── Card rows ───────────────────────────────────────────────────
            List {
                ForEach(draftCards.indices, id: \.self) { i in
                    CardPreviewRow(card: $draftCards[i]) {
                        draftCards.remove(at: i)
                    }
                }

                Button {
                    draftCards.append(CSVDraftCard(front: "", back: "", cardType: .basic, sourceRow: 0))
                } label: {
                    Label("Add Card", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .listStyle(.inset)

            Divider()

            // ── Footer ──────────────────────────────────────────────────────
            HStack(spacing: 16) {
                Text("\(enabledCount) of \(draftCards.count) cards selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Import \(enabledCount) Cards") {
                    runImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(enabledCount == 0)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func columnHeader(_ title: String, flex: Bool) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: flex ? .infinity : nil, alignment: .leading)
    }

    private var skippedErrorsPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Skipped Rows")
                .font(.subheadline).fontWeight(.semibold)
                .padding(.bottom, 2)
            ForEach(parseErrors, id: \.self) { err in
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Text(err).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 280, maxWidth: 400)
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: 14) {
            ProgressView().progressViewStyle(.circular)
            Text("Importing cards into \"\(deck.name)\"…").foregroundStyle(.secondary)
        }
    }

    // MARK: - Done

    private func doneView(count: Int) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("\(count) cards imported")
                    .font(.title2).fontWeight(.semibold)
                Text("into \"\(deck.name)\"")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button("Done", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    // MARK: - Actions

    private func parseFile(url: URL) {
        fileName = url.lastPathComponent
        phase = .parsing
        Task {
            let importer = CSVImporter(modelContext: modelContext)
            let result = await importer.parseOnly(from: url)
            draftCards = result.cards
            parseErrors = result.errors
            phase = .previewing
        }
    }

    private func runImport() {
        phase = .importing
        let approved = draftCards.filter(\.isEnabled)
        Task {
            let importer = CSVImporter(modelContext: modelContext)
            let result = await importer.importDraftCards(approved, into: deck)
            phase = .done(result.created)
        }
    }
}

// MARK: - Card preview row

private struct CardPreviewRow: View {

    @Binding var card: CSVDraftCard
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {

            // Enable toggle
            Toggle("", isOn: $card.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 20)

            // Type badge (tap to toggle)
            Button {
                card.cardType = card.cardType == .basic ? .cloze : .basic
            } label: {
                Text(card.cardType == .basic ? "Basic" : "Cloze")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(card.cardType == .basic ? Color.blue : Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(width: 46)
                    .background(
                        (card.cardType == .basic ? Color.blue : Color.orange).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Tap to toggle between Basic and Cloze")

            // Front text
            TextField("Front…", text: $card.front)
                .textFieldStyle(.plain)
                .font(.callout)

            Divider()
                .frame(height: 16)

            // Back text (or auto label for cloze)
            if card.cardType == .basic {
                TextField("Back…", text: $card.back)
                    .textFieldStyle(.plain)
                    .font(.callout)
            } else {
                Text("auto-generated from cloze markers")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Delete
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .opacity(0.7)
        }
        .padding(.vertical, 2)
        .opacity(card.isEnabled ? 1 : 0.45)
    }
}

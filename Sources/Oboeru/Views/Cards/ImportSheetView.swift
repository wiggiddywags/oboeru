import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet that lets the user import cards from a CSV or Anki .apkg file into a deck.
struct ImportSheetView: View {

    let deck: Deck
    let modelContext: ModelContext
    let onDismiss: () -> Void

    // MARK: - State

    enum ImportFormat: String, CaseIterable, Identifiable {
        case csv  = "CSV"
        case anki = "Anki (.apkg)"
        var id: String { rawValue }
    }

    enum Phase {
        case idle
        case parsingCSV
        case csvPreview                      // CSV: show editable table
        case importing
        case done(result: ImportSummary)
        case failed(message: String)
    }

    struct ImportSummary {
        let decksCreated: Int
        let cardsCreated: Int
        let cardsSkipped: Int
        let errors: [String]
        let format: ImportFormat
    }

    @State private var selectedFormat: ImportFormat = .csv
    @State private var showFilePicker = false
    @State private var phase: Phase = .idle
    // CSV preview state
    @State private var draftCards: [CSVDraftCard] = []
    @State private var parseErrors: [String] = []
    @State private var showParseErrors = false
    @State private var csvFileName = ""
    private var enabledCount: Int { draftCards.filter(\.isEnabled).count }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Cards")
                        .font(.title2).fontWeight(.semibold)
                    if case .csvPreview = phase, !csvFileName.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text").font(.caption2)
                            Text(csvFileName).font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .csvPreview = phase {
                    Button("Choose Different File") { showFilePicker = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // ── Content ──
            if case .csvPreview = phase {
                csvPreviewTable
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Format picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Format")
                                .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)

                            Picker("Format", selection: $selectedFormat) {
                                ForEach(ImportFormat.allCases) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!isIdle)
                        }

                        // Format description
                        formatDescriptionView

                        // Action / result area
                        switch phase {
                        case .idle:
                            idleView
                        case .parsingCSV:
                            HStack(spacing: 12) {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                                Text("Parsing file…").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        case .importing:
                            importingView
                        case .done(let summary):
                            doneView(summary: summary)
                        case .failed(let msg):
                            failedView(message: msg)
                        case .csvPreview:
                            EmptyView()
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(width: 760, height: 580)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelected(result)
        }
    }

    // MARK: - CSV preview table (inline)

    private var csvPreviewTable: some View {
        VStack(spacing: 0) {

            // Stats / action bar
            HStack(spacing: 14) {
                Label("\(draftCards.count) cards parsed", systemImage: "tablecells")
                    .font(.subheadline).foregroundStyle(.secondary)

                if !parseErrors.isEmpty {
                    Button {
                        showParseErrors.toggle()
                    } label: {
                        Label("\(parseErrors.count) skipped", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showParseErrors, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Skipped Rows").font(.subheadline).fontWeight(.semibold)
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
                }

                Spacer()

                Button("Select All") {
                    for i in draftCards.indices { draftCards[i].isEnabled = true }
                }
                .buttonStyle(.plain).font(.subheadline).foregroundStyle(Color.accentColor)

                Button("Deselect All") {
                    for i in draftCards.indices { draftCards[i].isEnabled = false }
                }
                .buttonStyle(.plain).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(.bar)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Color.clear.frame(width: 46)
                Text("Front").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(height: 14).padding(.horizontal, 4)
                Text("Back").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6))

            Divider()

            // Rows
            List {
                ForEach(draftCards.indices, id: \.self) { i in
                    ImportPreviewRow(card: $draftCards[i]) {
                        draftCards.remove(at: i)
                    }
                }
                Button {
                    draftCards.append(CSVDraftCard(front: "", back: "", cardType: .basic, sourceRow: 0))
                } label: {
                    Label("Add Card", systemImage: "plus.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            .listStyle(.inset)

            Divider()

            // Footer
            HStack(spacing: 16) {
                Text("\(enabledCount) of \(draftCards.count) selected")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Import \(enabledCount) Cards") {
                    commitCSVImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(enabledCount == 0)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var formatDescriptionView: some View {
        let (title, bullets): (String, [String]) = {
            switch selectedFormat {
            case .csv:
                return (
                    "CSV file with one card per row.",
                    [
                        "Basic cards: Front, Back [, Front Image URL, Back Image URL]",
                        "Cloze cards: single Text column with {{gap}} markers",
                        "First row may be a header (automatically detected)",
                        "Image columns accept http://, https://, or file:// URLs"
                    ]
                )
            case .anki:
                return (
                    "Anki package (.apkg) exported from Anki.",
                    [
                        "Imports all Basic and Cloze note types",
                        "Preserves scheduling state where possible",
                        "Embedded images are extracted automatically",
                        "Requires Anki 2.1+ (collection.anki2 or .anki21)"
                    ]
                )
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Text(bullet).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var idleView: some View {
        Button {
            showFilePicker = true
        } label: {
            Label("Choose File…", systemImage: "folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var importingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
            Text("Importing…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func doneView(summary: ImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Import Complete", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 6) {
                if summary.format == .anki && summary.decksCreated > 0 {
                    summaryRow(label: "Decks created", value: "\(summary.decksCreated)")
                }
                summaryRow(label: "Cards imported", value: "\(summary.cardsCreated)")
                if summary.cardsSkipped > 0 {
                    summaryRow(label: "Cards skipped", value: "\(summary.cardsSkipped)")
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if !summary.errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Warnings")
                        .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(summary.errors.prefix(10), id: \.self) { err in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if summary.errors.count > 10 {
                                Text("…and \(summary.errors.count - 10) more")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(maxHeight: 80)
                }
            }

            Button("Import Another File") {
                phase = .idle
            }
            .buttonStyle(.bordered)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Import Failed", systemImage: "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Try Again") { phase = .idle }
                .buttonStyle(.bordered)
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .font(.subheadline)
    }

    // MARK: - Helpers

    private var isIdle: Bool {
        if case .idle = phase { return true }
        return false
    }

    private var allowedTypes: [UTType] {
        switch selectedFormat {
        case .csv:  return [.commaSeparatedText, .tabSeparatedText, .plainText]
        case .anki: return [UTType(filenameExtension: "apkg") ?? .data]
        }
    }

    // MARK: - File handling

    private func handleFileSelected(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            phase = .failed(message: error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            switch selectedFormat {
            case .csv:
                // Parse first, show editable preview
                csvFileName = url.lastPathComponent
                phase = .parsingCSV
                Task { await parseCSV(url: url) }
            case .anki:
                phase = .importing
                Task { await runAnkiImport(url: url) }
            }
        }
    }

    @MainActor
    private func parseCSV(url: URL) async {
        let importer = CSVImporter(modelContext: modelContext)
        let result = await importer.parseOnly(from: url)
        if result.cards.isEmpty && !result.errors.isEmpty {
            phase = .failed(message: result.errors.first ?? "Could not parse file")
        } else {
            draftCards = result.cards
            parseErrors = result.errors
            phase = .csvPreview
        }
    }

    @MainActor
    private func commitCSVImport() {
        phase = .importing
        let approved = draftCards.filter(\.isEnabled)
        Task {
            let importer = CSVImporter(modelContext: modelContext)
            let result = await importer.importDraftCards(approved, into: deck)
            phase = .done(result: ImportSummary(
                decksCreated: 0,
                cardsCreated: result.created,
                cardsSkipped: result.skipped,
                errors: result.errors,
                format: .csv
            ))
        }
    }

    @MainActor
    private func runAnkiImport(url: URL) async {
        do {
            let ankiDecks = try AnkiImporter.import(from: url)
            var totalCards = 0
            for ankiDeck in ankiDecks {
                let d = Deck(name: ankiDeck.name, colorHex: ankiDeck.colorHex)
                modelContext.insert(d)
                for ac in ankiDeck.cards {
                    if ac.cardType == .cloze, let ct = ac.clozeText {
                        let siblings = ClozeParser.siblings(for: ct)
                        for s in siblings {
                            let card = OboerCard(deck: d, cardType: .cloze,
                                                frontText: s.maskedText, backText: s.fullText,
                                                clozeText: ct, clozeOrdinal: s.ordinal)
                            card.tags = ac.tags
                            modelContext.insert(card)
                        }
                    } else {
                        let card = OboerCard(deck: d, cardType: .basic,
                                            frontText: ac.frontText, backText: ac.backText)
                        card.tags = ac.tags
                        modelContext.insert(card)
                    }
                    totalCards += 1
                }
            }
            try modelContext.save()
            phase = .done(result: ImportSummary(
                decksCreated: ankiDecks.count,
                cardsCreated: totalCards,
                cardsSkipped: 0,
                errors: [],
                format: .anki
            ))
        } catch {
            phase = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - Inline preview row (shared with ImportSheetView)

struct ImportPreviewRow: View {

    @Binding var card: CSVDraftCard
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $card.isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 20)

            Button {
                card.cardType = card.cardType == .basic ? .cloze : .basic
            } label: {
                Text(card.cardType == .basic ? "Basic" : "Cloze")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(card.cardType == .basic ? Color.blue : Color.orange)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(width: 46)
                    .background(
                        (card.cardType == .basic ? Color.blue : Color.orange).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Tap to toggle Basic / Cloze")

            TextField("Front…", text: $card.front)
                .textFieldStyle(.plain).font(.callout)

            Divider().frame(height: 16)

            if card.cardType == .basic {
                TextField("Back…", text: $card.back)
                    .textFieldStyle(.plain).font(.callout)
            } else {
                Text("auto-generated from cloze markers")
                    .font(.callout).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .opacity(0.7)
        }
        .padding(.vertical, 2)
        .opacity(card.isEnabled ? 1 : 0.45)
    }
}

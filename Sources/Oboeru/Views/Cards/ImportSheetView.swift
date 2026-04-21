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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──
            HStack {
                Text("Import Cards")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // ── Content ──
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
                    case .importing:
                        importingView
                    case .done(let summary):
                        doneView(summary: summary)
                    case .failed(let msg):
                        failedView(message: msg)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 460)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelected(result)
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
            phase = .importing
            Task {
                await runImport(url: url)
            }
        }
    }

    @MainActor
    private func runImport(url: URL) async {
        switch selectedFormat {
        case .csv:
            let importer = CSVImporter(modelContext: modelContext)
            let result = await importer.importCSV(from: url, into: deck)
            if result.created == 0 && !result.errors.isEmpty {
                phase = .failed(message: result.errors.first ?? "Unknown error")
            } else {
                phase = .done(result: ImportSummary(
                    decksCreated: 0,
                    cardsCreated: result.created,
                    cardsSkipped: result.skipped,
                    errors: result.errors,
                    format: .csv
                ))
            }

        case .anki:
            let importer = AnkiImporter(modelContext: modelContext)
            let result = await importer.importAPKG(from: url)
            if result.cardsCreated == 0 && !result.errors.isEmpty {
                phase = .failed(message: result.errors.first ?? "Unknown error")
            } else {
                phase = .done(result: ImportSummary(
                    decksCreated: result.decksCreated,
                    cardsCreated: result.cardsCreated,
                    cardsSkipped: result.cardsSkipped,
                    errors: result.errors,
                    format: .anki
                ))
            }
        }
    }
}

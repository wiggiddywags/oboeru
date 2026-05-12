import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DocumentAIImportSheet: View {

    let allDecks:     [Deck]
    let defaultDeck:  Deck?
    let modelContext: ModelContext
    let onDismiss:    () -> Void

    @AppStorage("oboeru.claudeModel") private var modelRaw = ClaudeModel.haiku.rawValue
    @State private var fileURL:     URL?   = nil
    @State private var topic:       String = ""
    @State private var cardCount:   Int    = 20
    @State private var showPicker          = false
    @State private var phase               = Phase.idle
    @State private var generatedCards:     [AIGeneratedCard] = []
    @State private var showPreview         = false
    @State private var errorMessage:       String? = nil

    enum Phase { case idle, extracting, generating, done, failed }

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRaw) ?? .haiku }

    var body: some View {
        if showPreview {
            AIImportPreviewSheet(
                cards: generatedCards,
                sourceTitle: fileURL?.lastPathComponent ?? "Document",
                allDecks: allDecks,
                defaultDeck: defaultDeck,
                modelContext: modelContext,
                onDismiss: onDismiss
            )
        } else {
            mainView
        }
    }

    // MARK: - Main view

    private var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Import from Document", systemImage: "doc.fill")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Cancel", action: onDismiss)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Step 1 — Pick file
                    VStack(alignment: .leading, spacing: 12) {
                        stepLabel(1, "Document")
                        if let url = fileURL {
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: url))
                                    .font(.title2).foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).fontWeight(.medium).lineLimit(1)
                                    Text(url.pathExtension.uppercased())
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Change") { showPicker = true }.buttonStyle(.bordered)
                            }
                            .padding(14)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            Button { showPicker = true } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Choose PDF, TXT, or Markdown…")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                        Text("Supported: PDF, TXT, Markdown (.md)")
                            .font(.caption).foregroundStyle(.tertiary)
                    }

                    // Step 2 — Options
                    VStack(alignment: .leading, spacing: 12) {
                        stepLabel(2, "Options")
                        TextField("Topic or focus — e.g. \"Python decorators\"", text: $topic)
                            .textFieldStyle(.roundedBorder)
                        Stepper("Generate \(cardCount) cards", value: $cardCount, in: 5...50, step: 5)
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.accentColor).font(.caption)
                            Text("Model: **\(model.displayName)** — \(model.subtitle)")
                                .font(.caption)
                            Spacer()
                            Button("Change in Settings ⌘,") {
                                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.tertiary)
                        }
                    }

                    // Error banner
                    if let msg = errorMessage {
                        errorBanner(msg)
                    }

                    // No-key warning
                    if !KeychainService.hasAPIKey {
                        noKeyBanner
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                generateButton
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 500)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: [.pdf, .plainText,
                                   UTType(filenameExtension: "md") ?? .plainText,
                                   UTType(filenameExtension: "markdown") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result { fileURL = urls.first; errorMessage = nil }
        }
    }

    // MARK: - Generate

    @ViewBuilder
    private var generateButton: some View {
        Button {
            startGeneration()
        } label: {
            HStack(spacing: 6) {
                if phase == .extracting || phase == .generating {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(phase == .extracting ? "Extracting…" :
                     phase == .generating ? "Generating cards…" : "Generate Cards")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(fileURL == nil || phase == .extracting || phase == .generating || !KeychainService.hasAPIKey)
    }

    private func startGeneration() {
        guard let url  = fileURL,
              let key  = KeychainService.loadAPIKey(), !key.isEmpty else {
            errorMessage = "Add a Claude API key in Settings (⌘,) first."
            return
        }
        errorMessage = nil
        phase = .extracting
        Task {
            do {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                let text = try ClaudeService.extractText(from: url)
                await MainActor.run { phase = .generating }
                let cards = try await ClaudeService.generateCards(
                    from: text, topic: topic, cardCount: cardCount, model: model, apiKey: key)
                await MainActor.run { generatedCards = cards; phase = .done; showPreview = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; phase = .failed }
            }
        }
    }

    // MARK: - Sub-views

    private func stepLabel(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white).frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(title).font(.headline)
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Label(msg, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red).font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var noKeyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            Text("No API key set. Open **Settings** (⌘,) → AI Import to add one.")
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":            return "doc.fill"
        case "md", "markdown": return "doc.text.fill"
        default:               return "doc"
        }
    }
}

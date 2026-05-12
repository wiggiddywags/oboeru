import SwiftUI
import SwiftData

struct URLAIImportSheet: View {

    let allDecks:     [Deck]
    let defaultDeck:  Deck?
    let modelContext: ModelContext
    let onDismiss:    () -> Void

    @AppStorage("oboeru.claudeModel") private var modelRaw = ClaudeModel.haiku.rawValue
    @State private var urlText:       String = ""
    @State private var topic:         String = ""
    @State private var cardCount:     Int    = 20
    @State private var phase                 = Phase.idle
    @State private var generatedCards:       [AIGeneratedCard] = []
    @State private var pageTitle:     String = ""
    @State private var showPreview           = false
    @State private var errorMessage:         String? = nil

    enum Phase { case idle, fetching, generating, done, failed }

    private var model: ClaudeModel { ClaudeModel(rawValue: modelRaw) ?? .haiku }

    var body: some View {
        if showPreview {
            AIImportPreviewSheet(
                cards: generatedCards,
                sourceTitle: pageTitle.isEmpty ? urlText : pageTitle,
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
                Label("Import from URL", systemImage: "globe")
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Cancel", action: onDismiss)
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // Step 1 — URL
                    VStack(alignment: .leading, spacing: 12) {
                        stepLabel(1, "URL")
                        TextField("https://docs.python.org/3/tutorial/…", text: $urlText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { startGeneration() }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Works great with:")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach([
                                ("doc.text",          "Documentation & tutorials"),
                                ("globe",             "Wikipedia pages"),
                                ("newspaper",         "Blog posts & articles"),
                                ("note.text",         "Course notes & syllabi"),
                            ], id: \.0) { icon, label in
                                Label(label, systemImage: icon)
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Step 2 — Options
                    VStack(alignment: .leading, spacing: 12) {
                        stepLabel(2, "Options")
                        TextField("Topic or focus (optional)", text: $topic)
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

            HStack {
                Spacer()
                generateButton
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520, height: 500)
    }

    // MARK: - Generate

    @ViewBuilder
    private var generateButton: some View {
        Button {
            startGeneration()
        } label: {
            HStack(spacing: 6) {
                if phase == .fetching || phase == .generating {
                    ProgressView().scaleEffect(0.75)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(phase == .fetching   ? "Fetching page…" :
                     phase == .generating ? "Generating cards…" : "Generate Cards")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty ||
                  phase == .fetching || phase == .generating ||
                  !KeychainService.hasAPIKey)
    }

    private func startGeneration() {
        let trimURL = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimURL.isEmpty,
              let key = KeychainService.loadAPIKey(), !key.isEmpty else {
            errorMessage = "Add a Claude API key in Settings (⌘,) first."
            return
        }
        errorMessage = nil
        phase = .fetching
        Task {
            do {
                let (title, body) = try await ClaudeService.fetchWebContent(from: trimURL)
                await MainActor.run { pageTitle = title; phase = .generating }
                let hint  = topic.isEmpty ? title : topic
                let cards = try await ClaudeService.generateCards(
                    from: body, topic: hint, cardCount: cardCount, model: model, apiKey: key)
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
}

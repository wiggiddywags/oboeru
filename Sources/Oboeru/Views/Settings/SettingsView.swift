import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @State private var settings: AppSettings?

    var body: some View {
        Group {
            if let settings {
                SettingsForm(settings: settings)
            } else {
                ProgressView()
            }
        }
        .onAppear { settings = AppSettings.fetchOrCreate(in: modelContext) }
    }
}

// MARK: - Tabbed form

private struct SettingsForm: View {

    @Bindable var settings: AppSettings

    var body: some View {
        TabView {
            StudySettingsTab(settings: settings)
                .tabItem { Label("Study", systemImage: "brain.head.profile") }
            AISettingsTab()
                .tabItem { Label("AI Import", systemImage: "sparkles") }
        }
        .frame(width: 500, height: 380)
    }
}

// MARK: - Study tab

private struct StudySettingsTab: View {

    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Daily Limits") {
                Stepper("New cards per day: \(settings.dailyNewCardLimit)",
                        value: $settings.dailyNewCardLimit, in: 1...999)
                Stepper("Reviews per day: \(settings.dailyReviewLimit)",
                        value: $settings.dailyReviewLimit, in: 1...9_999)
            }

            Section("Interleaving") {
                Toggle("Enable interleaving", isOn: $settings.interleavingEnabled)
                if settings.interleavingEnabled {
                    Stepper("Block size: \(settings.interleavingBlockSize) cards",
                            value: $settings.interleavingBlockSize, in: 2...20)
                    Text("Cards from one deck before rotating to the next.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Algorithm", value: "FSRS-5")
                LabeledContent("Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.dailyNewCardLimit)     { try? settings.modelContext?.save() }
        .onChange(of: settings.dailyReviewLimit)      { try? settings.modelContext?.save() }
        .onChange(of: settings.interleavingEnabled)   { try? settings.modelContext?.save() }
        .onChange(of: settings.interleavingBlockSize) { try? settings.modelContext?.save() }
    }
}

// MARK: - AI tab

private struct AISettingsTab: View {

    @AppStorage("oboeru.claudeModel") private var selectedModel: String = ClaudeModel.haiku.rawValue
    @State private var apiKey      = ""
    @State private var showKey     = true   // default visible so ⌘V paste always works
    @State private var keyStatus   = KeyStatus.untested
    @State private var isTesting   = false

    enum KeyStatus {
        case untested, valid, invalid(String)
        var tint: Color { switch self { case .valid: .green; case .invalid: .red; default: .secondary } }
        var icon: String { switch self { case .valid: "checkmark.seal.fill"; case .invalid: "xmark.seal.fill"; default: "key.fill" } }
        var label: String { switch self { case .valid: "Valid key"; case .invalid(let m): m; default: "Not verified" } }
    }

    var body: some View {
        Form {
            // API Key section
            Section {
                HStack(spacing: 8) {
                    Group {
                        if showKey {
                            TextField("sk-ant-…", text: $apiKey)
                        } else {
                            SecureField("sk-ant-…", text: $apiKey)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.plain)

                    // Paste from clipboard — reliable on macOS regardless of field focus
                    Button {
                        if let str = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            apiKey    = str
                            keyStatus = .untested
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Paste from clipboard")

                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(showKey ? "Hide key" : "Show key")
                }

                HStack(spacing: 8) {
                    Image(systemName: keyStatus.icon)
                        .foregroundStyle(keyStatus.tint)
                    Text(keyStatus.label)
                        .font(.caption).foregroundStyle(keyStatus.tint)
                    Spacer()
                    if isTesting { ProgressView().scaleEffect(0.75) }
                    Button("Save & Test") { saveAndTest() }
                        .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
                    if KeychainService.hasAPIKey {
                        Button("Remove") {
                            KeychainService.deleteAPIKey()
                            apiKey    = ""
                            keyStatus = .untested
                        }
                        .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Claude API Key")
            } footer: {
                HStack(spacing: 4) {
                    Text("Get a key at")
                    Link("console.anthropic.com/api-keys",
                         destination: URL(string: "https://console.anthropic.com/api-keys")!)
                    Text("· Stored securely in macOS Keychain")
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            // Model picker
            Section("Model") {
                ForEach(ClaudeModel.allCases, id: \.rawValue) { claudeModel in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(claudeModel.displayName).fontWeight(.medium)
                            Text(claudeModel.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedModel == claudeModel.rawValue {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedModel = claudeModel.rawValue }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { apiKey = KeychainService.loadAPIKey() ?? "" }
    }

    private func saveAndTest() {
        let key = apiKey.trimmingCharacters(in: .whitespaces)
        KeychainService.saveAPIKey(key)
        isTesting  = true
        keyStatus  = .untested
        Task {
            do {
                try await ClaudeService.validateKey(key)
                await MainActor.run { keyStatus = .valid;              isTesting = false }
            } catch {
                await MainActor.run { keyStatus = .invalid(error.localizedDescription); isTesting = false }
            }
        }
    }
}

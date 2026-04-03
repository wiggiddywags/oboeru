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
        .frame(width: 420)
        .onAppear {
            settings = AppSettings.fetchOrCreate(in: modelContext)
        }
    }
}

private struct SettingsForm: View {

    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Daily Limits") {
                Stepper("New cards per day: \(settings.dailyNewCardLimit)", value: $settings.dailyNewCardLimit, in: 1...999)
                Stepper("Reviews per day: \(settings.dailyReviewLimit)", value: $settings.dailyReviewLimit, in: 1...9999)
            }

            Section("Interleaving") {
                Toggle("Enable interleaving", isOn: $settings.interleavingEnabled)
                if settings.interleavingEnabled {
                    Stepper(
                        "Block size: \(settings.interleavingBlockSize) cards",
                        value: $settings.interleavingBlockSize,
                        in: 2...20
                    )
                    Text("Cards from one deck before rotating to the next.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Algorithm", value: "FSRS-5")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: settings.dailyNewCardLimit)  { try? settings.modelContext?.save() }
        .onChange(of: settings.dailyReviewLimit)   { try? settings.modelContext?.save() }
        .onChange(of: settings.interleavingEnabled) { try? settings.modelContext?.save() }
        .onChange(of: settings.interleavingBlockSize) { try? settings.modelContext?.save() }
    }
}

import SwiftUI
import SwiftData

@main
struct OboerApp: App {

    let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands() }
        .defaultSize(width: 1200, height: 750)

        Settings {
            SettingsView()
        }
        .modelContainer(container)
    }

    // MARK: - Persistent store

    /// Builds a ModelContainer that always writes to the same file in
    /// ~/Library/Application Support/Oboeru/, so data survives restarts
    /// regardless of code-signing / sandbox state during development.
    private static func makeContainer() -> ModelContainer {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Oboeru", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)

        let storeURL = appSupport.appendingPathComponent("oboeru.store")

        let schema = Schema([
            Deck.self,
            OboerCard.self,
            OboerReviewLog.self,
            AppSettings.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // If the existing store is incompatible (schema migration failure),
            // delete it and start fresh rather than crashing.
            print("⚠️  ModelContainer failed (\(error)). Recreating store at \(storeURL.path).")
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove companion files
            for ext in ["-shm", "-wal"] {
                try? FileManager.default.removeItem(
                    at: storeURL.deletingPathExtension()
                        .appendingPathExtension(storeURL.pathExtension + ext))
            }
            return try! ModelContainer(for: schema, configurations: config)
        }
    }
}

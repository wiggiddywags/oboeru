import SwiftUI
import SwiftData

@main
struct OboerApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Deck.self,
            OboerCard.self,
            OboerReviewLog.self,
            AppSettings.self,
        ])
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { AppCommands() }
        .defaultSize(width: 1200, height: 750)
        .windowMinimumSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
        .modelContainer(for: [AppSettings.self])
    }
}

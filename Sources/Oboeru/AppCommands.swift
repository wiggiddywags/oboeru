import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        // Replace default New Item with our own
        CommandGroup(replacing: .newItem) {
            Button("New Deck…") {
                NotificationCenter.default.post(name: .newDeckRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Card…") {
                NotificationCenter.default.post(name: .newCardRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        // Study menu
        CommandMenu("Study") {
            Button("Study Selected Deck") {
                NotificationCenter.default.post(name: .studyRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Study All Due") {
                NotificationCenter.default.post(name: .studyAllRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}

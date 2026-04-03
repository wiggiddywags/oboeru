import SwiftUI

struct DeckEditorSheet: View {

    @State private var name: String = ""
    @State private var selectedColor: String = "#5E9CF0"
    @State private var selectedIcon: String = "rectangle.stack"

    var existingDeck: Deck?
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void

    private let colors = [
        "#5E9CF0", "#FF6B6B", "#51CF66", "#FF922B",
        "#CC5DE8", "#20C997", "#F59F00", "#74C0FC"
    ]

    private let icons = [
        "rectangle.stack", "brain.head.profile", "book.fill",
        "music.note", "globe", "flask.fill", "cpu", "pencil",
        "numbers", "doc.text.fill", "paintpalette.fill", "figure.run"
    ]

    init(existingDeck: Deck? = nil, onSave: @escaping (String, String, String) -> Void, onCancel: @escaping () -> Void) {
        self.existingDeck = existingDeck
        self.onSave = onSave
        self.onCancel = onCancel
        if let deck = existingDeck {
            _name = State(initialValue: deck.name)
            _selectedColor = State(initialValue: deck.colorHex)
            _selectedIcon = State(initialValue: deck.iconName)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(existingDeck == nil ? "New Deck" : "Edit Deck")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Preview
            deckPreview
                .padding(.bottom, 24)

            Divider()

            Form {
                Section {
                    TextField("Deck Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Color") {
                    colorPicker
                }

                Section("Icon") {
                    iconPicker
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, selectedColor, selectedIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .frame(width: 400, height: 520)
    }

    private var deckPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedIcon)
                .font(.title2)
                .foregroundStyle(Color(hex: selectedColor) ?? .accentColor)
                .frame(width: 36, height: 36)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Text(name.isEmpty ? "Deck Name" : name)
                .font(.headline)
                .foregroundStyle(name.isEmpty ? .secondary : .primary)
        }
        .padding(.horizontal, 24)
    }

    private var colorPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
            ForEach(colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .blue)
                    .frame(width: 28, height: 28)
                    .overlay {
                        if hex == selectedColor {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.white)
                        }
                    }
                    .onTapGesture { selectedColor = hex }
            }
        }
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 6), spacing: 8) {
            ForEach(icons, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(icon == selectedIcon ? Color.accentColor.opacity(0.15) : Color.clear)
                    .background(.quaternary.opacity(icon == selectedIcon ? 0 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        if icon == selectedIcon {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        }
                    }
                    .onTapGesture { selectedIcon = icon }
            }
        }
    }
}

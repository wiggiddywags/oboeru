import SwiftUI
import SwiftData

struct CardEditorSheet: View {

    @State private var vm: CardEditorViewModel
    let onDismiss: () -> Void

    init(existingCard: OboerCard? = nil, deck: Deck, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: CardEditorViewModel(editing: existingCard, deck: deck, modelContext: modelContext))
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(vm.isEditing ? "Edit Card" : "New Card")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                // Card type picker (only when creating new)
                if !vm.isEditing {
                    Picker("Type", selection: $vm.cardType) {
                        ForEach(CardType.allCases, id: \.self) { type in
                            Text(type == .basic ? "Basic" : "Cloze").tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Editor body
            ScrollView {
                switch vm.cardType {
                case .basic:
                    BasicCardEditorBody(front: $vm.frontText, back: $vm.backText)
                case .cloze:
                    ClozeCardEditorBody(
                        clozeText: $vm.clozeText,
                        isValid: vm.clozeIsValid,
                        siblingCount: vm.clozeSiblingCount
                    )
                    .onChange(of: vm.clozeText) { vm.updateClozePreview() }
                }
            }
            .padding(24)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(vm.isEditing ? "Save Changes" : "Add Card") {
                    try? vm.save()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canSave)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
        }
        .frame(width: 560, height: 420)
    }
}

// MARK: - Basic card editor

private struct BasicCardEditorBody: View {

    @Binding var front: String
    @Binding var back: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorField(label: "Front", placeholder: "Question or term…", text: $front)
            editorField(label: "Back", placeholder: "Answer or definition…", text: $back)
        }
    }

    private func editorField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 80)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

// MARK: - Cloze card editor

private struct ClozeCardEditorBody: View {

    @Binding var clozeText: String
    let isValid: Bool
    let siblingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloze Text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("Use {{answer}} or {{answer::hint}} to mark gaps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $clozeText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if clozeText.isEmpty {
                        Text("e.g. The {{capital::city}} of France is {{Paris}}.")
                            .foregroundStyle(.tertiary)
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }

            // Validation feedback
            if !clozeText.isEmpty {
                if isValid {
                    Label(
                        "\(siblingCount) card\(siblingCount == 1 ? "" : "s") will be created",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Label("Add at least one {{gap}} marker", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

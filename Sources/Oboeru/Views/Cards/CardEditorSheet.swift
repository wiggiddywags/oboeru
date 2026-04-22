import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

            ScrollView {
                VStack(spacing: 20) {
                    switch vm.cardType {
                    case .basic:
                        BasicCardEditorBody(
                            front: $vm.frontText,
                            back: $vm.backText,
                            frontImageData: $vm.frontImageData,
                            backImageData: $vm.backImageData
                        )
                    case .cloze:
                        ClozeCardEditorBody(
                            clozeText: $vm.clozeText,
                            isValid: vm.clozeIsValid,
                            siblingCount: vm.clozeSiblingCount,
                            frontImageData: $vm.frontImageData,
                            backImageData: $vm.backImageData
                        )
                        .onChange(of: vm.clozeText) { vm.updateClozePreview() }
                    }
                }
                .padding(24)
            }

            Divider()

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
        .frame(width: 600, height: 520)
    }
}

// MARK: - Basic card editor

private struct BasicCardEditorBody: View {

    @Binding var front: String
    @Binding var back: String
    @Binding var frontImageData: Data?
    @Binding var backImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            editorSection(label: "Front", placeholder: "Question or term…", text: $front, imageData: $frontImageData)
            editorSection(label: "Back",  placeholder: "Answer or definition…", text: $back,  imageData: $backImageData)
        }
    }

    private func editorSection(label: String, placeholder: String, text: Binding<String>, imageData: Binding<Data?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 70)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                    }
                }

            CardImagePicker(imageData: imageData)
        }
    }
}

// MARK: - Cloze card editor

private struct ClozeCardEditorBody: View {

    @Binding var clozeText: String
    let isValid: Bool
    let siblingCount: Int
    @Binding var frontImageData: Data?
    @Binding var backImageData: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloze Text")
                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Text("Use {{answer}} or {{answer::hint}} to mark gaps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: $clozeText)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if clozeText.isEmpty {
                        Text("e.g. The {{capital::city}} of France is {{Paris}}.")
                            .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                    }
                }

            if !clozeText.isEmpty {
                if isValid {
                    Label("\(siblingCount) card\(siblingCount == 1 ? "" : "s") will be created", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("Add at least one {{gap}} marker", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Image (front)").font(.caption).foregroundStyle(.secondary)
                    CardImagePicker(imageData: $frontImageData)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Image (back)").font(.caption).foregroundStyle(.secondary)
                    CardImagePicker(imageData: $backImageData)
                }
            }
        }
    }
}

// MARK: - Image picker component

struct CardImagePicker: View {

    @Binding var imageData: Data?
    @State private var isTargeted = false
    @State private var showFilePicker = false

    var body: some View {
        Group {
            if let data = imageData, let nsImage = NSImage(data: data) {
                // Preview with remove button
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Button {
                        imageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            } else {
                // Drop zone
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.plus")
                        .font(.title2)
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                    Text("Drop image or")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Select…") { showFilePicker = true }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5])
                        )
                )
                .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                imageData = try? Data(contentsOf: url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data { DispatchQueue.main.async { imageData = data } }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let imgData = try? Data(contentsOf: url) {
                    DispatchQueue.main.async { imageData = imgData }
                }
            }
            return true
        }

        return false
    }
}

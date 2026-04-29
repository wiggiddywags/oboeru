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
                    .font(.title2).fontWeight(.semibold)
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
                        BasicCardEditorBody(vm: vm)
                    case .cloze:
                        ClozeCardEditorBody(vm: vm)
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
        .frame(width: 640, height: 660)
    }
}

// MARK: - Basic card editor

private struct BasicCardEditorBody: View {
    @Bindable var vm: CardEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardSide(
                label: "Front",
                placeholder: "Question or term…",
                rtfData: $vm.frontRTFData,
                plainText: $vm.frontText,
                imageData: $vm.frontImageData,
                audioData: $vm.frontAudioData, audioExt: $vm.frontAudioExt,
                videoData: $vm.frontVideoData, videoExt: $vm.frontVideoExt,
                sketchData: $vm.frontSketchData
            )
            cardSide(
                label: "Back",
                placeholder: "Answer or definition…",
                rtfData: $vm.backRTFData,
                plainText: $vm.backText,
                imageData: $vm.backImageData,
                audioData: $vm.backAudioData, audioExt: $vm.backAudioExt,
                videoData: $vm.backVideoData, videoExt: $vm.backVideoExt,
                sketchData: $vm.backSketchData
            )
        }
    }

    private func cardSide(
        label: String,
        placeholder: String,
        rtfData: Binding<Data?>,
        plainText: Binding<String>,
        imageData: Binding<Data?>,
        audioData: Binding<Data?>, audioExt: Binding<String?>,
        videoData: Binding<Data?>, videoExt: Binding<String?>,
        sketchData: Binding<Data?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)

            RichTextEditorWithToolbar(
                rtfData: rtfData,
                plainText: plainText,
                minHeight: 80
            )

            // Image / GIF
            CardImagePicker(imageData: imageData)

            // Audio
            CardMediaPickerRow(
                systemImage: "waveform",
                kindLabel: "Audio",
                acceptedTypes: [.audio],
                data: audioData,
                fileExt: audioExt
            )

            // Video
            CardMediaPickerRow(
                systemImage: "video",
                kindLabel: "Video",
                acceptedTypes: [.movie],
                data: videoData,
                fileExt: videoExt
            )

            // Sketch
            CardSketchPicker(sketchData: sketchData)
        }
    }
}

// MARK: - Cloze card editor

private struct ClozeCardEditorBody: View {
    @Bindable var vm: CardEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cloze Text")
                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Text("Use {{answer}} or {{answer::hint}} to mark gaps.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            TextEditor(text: $vm.clozeText)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if vm.clozeText.isEmpty {
                        Text("e.g. The {{capital::city}} of France is {{Paris}}.")
                            .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                    }
                }

            if !vm.clozeText.isEmpty {
                if vm.clozeIsValid {
                    Label("\(vm.clozeSiblingCount) card\(vm.clozeSiblingCount == 1 ? "" : "s") will be created",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("Add at least one {{gap}} marker", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Divider()

            // Media — shared across all sibling cards
            VStack(alignment: .leading, spacing: 8) {
                Text("Media (shared across all gaps)")
                    .font(.caption).foregroundStyle(.secondary).textCase(.uppercase)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Front image / GIF").font(.caption).foregroundStyle(.secondary)
                        CardImagePicker(imageData: $vm.frontImageData)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Back image / GIF").font(.caption).foregroundStyle(.secondary)
                        CardImagePicker(imageData: $vm.backImageData)
                    }
                }

                CardMediaPickerRow(
                    systemImage: "waveform",
                    kindLabel: "Front Audio",
                    acceptedTypes: [.audio],
                    data: $vm.frontAudioData,
                    fileExt: $vm.frontAudioExt
                )
                CardMediaPickerRow(
                    systemImage: "waveform",
                    kindLabel: "Back Audio",
                    acceptedTypes: [.audio],
                    data: $vm.backAudioData,
                    fileExt: $vm.backAudioExt
                )
                CardMediaPickerRow(
                    systemImage: "video",
                    kindLabel: "Front Video",
                    acceptedTypes: [.movie],
                    data: $vm.frontVideoData,
                    fileExt: $vm.frontVideoExt
                )
                CardMediaPickerRow(
                    systemImage: "video",
                    kindLabel: "Back Video",
                    acceptedTypes: [.movie],
                    data: $vm.backVideoData,
                    fileExt: $vm.backVideoExt
                )
            }
        }
    }
}

// MARK: - Image / GIF picker

struct CardImagePicker: View {

    @Binding var imageData: Data?
    @State private var isTargeted = false
    @State private var showFilePicker = false

    // Accept images AND GIF explicitly; also allow file URLs via drop
    private let imageTypes: [UTType] = [.image, .gif]

    var body: some View {
        Group {
            if let data = imageData {
                // Preview
                ZStack(alignment: .topTrailing) {
                    SmartImageView(data: data, maxHeight: 120)
                        .frame(maxWidth: .infinity)

                    Button {
                        imageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.black.opacity(0.6))
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
                    Text("Drop image / GIF or")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Select…") { showFilePicker = true }
                        .font(.caption).buttonStyle(.borderless)
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
                .background(
                    isTargeted ? Color.accentColor.opacity(0.05) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: imageTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                imageData = try? Data(contentsOf: url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Prefer raw file URL to preserve GIF frames exactly
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let d = item as? Data,
                      let url = URL(dataRepresentation: d, relativeTo: nil) else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let bytes = try? Data(contentsOf: url) {
                    DispatchQueue.main.async { imageData = bytes }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data { DispatchQueue.main.async { imageData = data } }
            }
            return true
        }

        return false
    }
}

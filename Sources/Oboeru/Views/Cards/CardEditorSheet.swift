import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Sheet

struct CardEditorSheet: View {

    @State private var vm: CardEditorViewModel
    let onDismiss: () -> Void

    private let deck: Deck
    private let modelContext: ModelContext

    init(existingCard: OboerCard? = nil, deck: Deck, modelContext: ModelContext, onDismiss: @escaping () -> Void) {
        _vm = State(initialValue: CardEditorViewModel(editing: existingCard, deck: deck, modelContext: modelContext))
        self.deck = deck
        self.modelContext = modelContext
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    switch vm.cardType {
                    case .basic:
                        BasicCardEditorBody(vm: vm)
                    case .cloze:
                        ClozeCardEditorBody(vm: vm)
                            .onChange(of: vm.clozeText) { _, _ in vm.updateClozePreview() }
                    }
                    metaRow
                }
            }
            .onChange(of: vm.cardType) { _, new in
                switch new {
                case .cloze:
                    if vm.clozeText.isEmpty && !vm.frontText.isEmpty {
                        vm.clozeText = vm.frontText
                        vm.updateClozePreview()
                    }
                case .basic:
                    if vm.frontText.isEmpty && !vm.clozeText.isEmpty {
                        vm.frontText = vm.clozeText
                    }
                }
            }
            Divider()
            actionBar
        }
        .frame(width: 640, height: 700)
        // Hidden ⌘1 / ⌘2 shortcuts
        .overlay(alignment: .topLeading) {
            if !vm.isEditing {
                ZStack {
                    Button("") { vm.cardType = .basic }.keyboardShortcut("1", modifiers: .command)
                    Button("") { vm.cardType = .cloze }.keyboardShortcut("2", modifiers: .command)
                }
                .opacity(0).frame(width: 0, height: 0).allowsHitTesting(false)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(vm.isEditing ? "Edit Card" : "New Card")
                    .font(.title2).fontWeight(.semibold)
                if !vm.isEditing {
                    Text("⌘1 Basic · ⌘2 Cloze")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !vm.isEditing {
                Picker("", selection: $vm.cardType) {
                    ForEach(CardType.allCases, id: \.self) { t in
                        Text(t == .basic ? "Basic" : "Cloze").tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 148)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    // MARK: - Meta row (tags + options)

    private var metaRow: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 28)
            HStack(alignment: .center, spacing: 0) {
                // Tags
                HStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Tags: chapter-1, vocab…", text: $vm.tagsText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .onChange(of: vm.tagsText) { _, _ in vm.parseTags() }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 28)

                Divider().frame(height: 28)

                // Reverse toggle
                Toggle(isOn: $vm.isReversed) {
                    Label("Reversed", systemImage: "arrow.left.arrow.right")
                        .font(.callout)
                        .help("The back becomes the question during study")
                }
                .toggleStyle(.checkbox)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            if !vm.isEditing {
                Button {
                    vm.parseTags()
                    try? vm.save()
                    vm = CardEditorViewModel(deck: deck, modelContext: modelContext)
                } label: {
                    Label("Add + Next", systemImage: "plus.square.on.square")
                }
                .disabled(!vm.canSave)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .help("Save and start a new card (⌘⇧↵)")
            }

            Button {
                vm.parseTags()
                try? vm.save()
                onDismiss()
            } label: {
                Label(vm.isEditing ? "Save Changes" : "Add Card",
                      systemImage: vm.isEditing ? "checkmark" : "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Step label

private struct StepLabel: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Media disclosure

private struct MediaDisclosure: View {
    let prefix: String          // "Front" / "Back" / "" (cloze shared)
    @Binding var isExpanded: Bool

    // Basic bindings
    var imageData: Binding<Data?>
    var audioData: Binding<Data?>
    var audioExt:  Binding<String?>
    var videoData: Binding<Data?>
    var videoExt:  Binding<String?>
    var sketchData: Binding<Data?>

    // Optional second image for cloze (back image)
    var backImageData: Binding<Data?>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Toggle button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "minus.circle.fill" : "photo.on.rectangle.angled")
                        .font(.caption)
                    Text(isExpanded ? "Hide media" : "Add media")
                        .font(.caption).fontWeight(.medium)
                    if !isExpanded {
                        mediaCountBadge
                    }
                }
                .foregroundStyle(hasMedia ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                VStack(spacing: 10) {
                    if let backImg = backImageData {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Front image").font(.caption).foregroundStyle(.secondary)
                                CardImagePicker(imageData: imageData)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Back image").font(.caption).foregroundStyle(.secondary)
                                CardImagePicker(imageData: backImg)
                            }
                        }
                    } else {
                        CardImagePicker(imageData: imageData)
                    }
                    CardMediaPickerRow(systemImage: "waveform", kindLabel: "\(prefix.isEmpty ? "" : prefix + " ")Audio",
                                       acceptedTypes: [.audio], data: audioData, fileExt: audioExt)
                    CardMediaPickerRow(systemImage: "video",    kindLabel: "\(prefix.isEmpty ? "" : prefix + " ")Video",
                                       acceptedTypes: [.movie], data: videoData, fileExt: videoExt)
                    if backImageData == nil {
                        CardSketchPicker(sketchData: sketchData)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var hasMedia: Bool {
        imageData.wrappedValue != nil ||
        audioData.wrappedValue != nil ||
        videoData.wrappedValue != nil ||
        sketchData.wrappedValue != nil ||
        backImageData?.wrappedValue != nil
    }

    @ViewBuilder
    private var mediaCountBadge: some View {
        let count = [imageData.wrappedValue, audioData.wrappedValue, videoData.wrappedValue,
                     sketchData.wrappedValue, backImageData?.wrappedValue].compactMap { $0 }.count
        if count > 0 {
            Text("\(count)")
                .font(.caption2).fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.accentColor, in: Capsule())
        }
    }
}

// MARK: - Basic card editor

private struct BasicCardEditorBody: View {
    @Bindable var vm: CardEditorViewModel
    @State private var showFrontMedia = false
    @State private var showBackMedia  = false

    var body: some View {
        VStack(spacing: 0) {
            sidePanel(
                step: 1,
                title: "Front",
                placeholder: "Question or term…",
                rtfData: $vm.frontRTFData,
                plainText: $vm.frontText,
                imageData: $vm.frontImageData,
                audioData: $vm.frontAudioData, audioExt: $vm.frontAudioExt,
                videoData: $vm.frontVideoData, videoExt: $vm.frontVideoExt,
                sketchData: $vm.frontSketchData,
                showMedia: $showFrontMedia
            )

            Divider()
                .padding(.horizontal, 28)

            sidePanel(
                step: 2,
                title: "Back",
                placeholder: "Answer or definition…",
                rtfData: $vm.backRTFData,
                plainText: $vm.backText,
                imageData: $vm.backImageData,
                audioData: $vm.backAudioData, audioExt: $vm.backAudioExt,
                videoData: $vm.backVideoData, videoExt: $vm.backVideoExt,
                sketchData: $vm.backSketchData,
                showMedia: $showBackMedia
            )
        }
        .onAppear {
            showFrontMedia = vm.frontImageData != nil || vm.frontAudioData != nil ||
                             vm.frontVideoData != nil || vm.frontSketchData != nil
            showBackMedia  = vm.backImageData  != nil || vm.backAudioData  != nil ||
                             vm.backVideoData  != nil || vm.backSketchData  != nil
        }
    }

    private func sidePanel(
        step: Int, title: String, placeholder: String,
        rtfData: Binding<Data?>, plainText: Binding<String>,
        imageData: Binding<Data?>,
        audioData: Binding<Data?>, audioExt: Binding<String?>,
        videoData: Binding<Data?>, videoExt: Binding<String?>,
        sketchData: Binding<Data?>,
        showMedia: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StepLabel(number: step, title: title)

            RichTextEditorWithToolbar(rtfData: rtfData, plainText: plainText, minHeight: 110)

            MediaDisclosure(
                prefix: title,
                isExpanded: showMedia,
                imageData: imageData,
                audioData: audioData, audioExt: audioExt,
                videoData: videoData, videoExt: videoExt,
                sketchData: sketchData
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cloze card editor

private struct ClozeCardEditorBody: View {
    @Bindable var vm: CardEditorViewModel
    @State private var showMedia = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Step header
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                StepLabel(number: 1, title: "Cloze Text")
                Text("Use {{answer}} or {{answer::hint}} to mark gaps.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            // Editor
            RichTextEditorWithToolbar(
                rtfData: $vm.clozeRTFData,
                plainText: $vm.clozeText,
                minHeight: 120
            )
            .overlay(alignment: .topLeading) {
                if vm.clozeText.isEmpty {
                    Text("e.g. The {{capital::city}} of France is {{Paris}}.")
                        .foregroundStyle(.tertiary).font(.body)
                        .padding(.leading, 12).padding(.top, 38)
                        .allowsHitTesting(false)
                }
            }

            // Validation feedback
            if !vm.clozeText.isEmpty {
                Group {
                    if vm.clozeIsValid {
                        Label("\(vm.clozeSiblingCount) card\(vm.clozeSiblingCount == 1 ? "" : "s") will be created",
                              systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Add at least one {{gap}} marker",
                              systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }

            Divider()

            // Shared media
            VStack(alignment: .leading, spacing: 14) {
                StepLabel(number: 2, title: "Shared Media")

                MediaDisclosure(
                    prefix: "",
                    isExpanded: $showMedia,
                    imageData: $vm.frontImageData,
                    audioData: $vm.frontAudioData, audioExt: $vm.frontAudioExt,
                    videoData: $vm.frontVideoData, videoExt: $vm.frontVideoExt,
                    sketchData: $vm.frontSketchData,
                    backImageData: $vm.backImageData
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            showMedia = vm.frontImageData != nil || vm.backImageData != nil ||
                        vm.frontAudioData != nil || vm.frontVideoData != nil
        }
    }
}

// MARK: - Image / GIF picker

struct CardImagePicker: View {

    @Binding var imageData: Data?
    @State private var isTargeted = false
    @State private var showFilePicker = false

    private let imageTypes: [UTType] = [.image, .gif]

    var body: some View {
        Group {
            if let data = imageData {
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
                        .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                )
                .background(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: imageTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                imageData = try? Data(contentsOf: url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
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

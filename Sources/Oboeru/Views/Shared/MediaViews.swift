import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

// MARK: - GIF detection

extension Data {
    /// True when the bytes start with GIF87a or GIF89a.
    var isAnimatedGIF: Bool {
        count >= 4 && prefix(4) == Data([0x47, 0x49, 0x46, 0x38])
    }
}

// MARK: - Animated NSImageView wrapper

/// Shows an NSImage and animates it when the data is a GIF.
struct AnimatedImageView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.animates = true
        v.imageScaling = .scaleProportionallyDown
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.image = NSImage(data: data)
        return v
    }

    func updateNSView(_ v: NSImageView, context: Context) {
        v.image = NSImage(data: data)
    }
}

// MARK: - SmartImageView (static PNG/JPG or animated GIF)

struct SmartImageView: View {
    let data: Data
    var maxHeight: CGFloat = 280
    var opacity: Double = 1.0

    var body: some View {
        Group {
            if data.isAnimatedGIF {
                AnimatedImageView(data: data)
                    .frame(maxHeight: maxHeight)
            } else if let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(opacity)
    }
}

// MARK: - Audio player

@Observable
final class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var progress: Double = 0
    var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(data: Data) {
        stop()
        player = try? AVAudioPlayer(data: data)
        player?.delegate = self
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            timer?.invalidate()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let p = self.player else { return }
                self.progress = p.currentTime / max(p.duration, 0.001)
            }
        }
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        timer?.invalidate()
        isPlaying = false
        progress = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        progress = 0
        timer?.invalidate()
    }
}

struct CardAudioPlayerView: View {
    let data: Data
    @State private var ctrl = AudioPlayerController()

    var body: some View {
        HStack(spacing: 10) {
            Button { ctrl.toggle() } label: {
                Image(systemName: ctrl.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            // Scrubber
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * ctrl.progress), height: 4)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)

            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .onAppear  { ctrl.load(data: data) }
        .onDisappear { ctrl.stop() }
    }

    private var timeLabel: String {
        let t = ctrl.isPlaying
            ? ctrl.duration * (1 - ctrl.progress)
            : ctrl.duration
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Video player

struct CardVideoPlayerView: View {
    let data: Data
    let fileExtension: String      // e.g. "mp4", "mov"

    @State private var player: AVPlayer?
    @State private var tempURL: URL?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: 260)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 160)
                    .overlay { ProgressView() }
            }
        }
        .onAppear  { loadVideo() }
        .onDisappear { cleanup() }
    }

    private func loadVideo() {
        let ext = fileExtension.isEmpty ? "mp4" : fileExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        try? data.write(to: url)
        tempURL = url
        player  = AVPlayer(url: url)
    }

    private func cleanup() {
        player?.pause()
        player = nil
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
    }
}

// MARK: - Compact media attachment row (used in CardEditorSheet)

struct CardMediaPickerRow: View {
    let systemImage: String
    let kindLabel: String          // "Audio", "Video"
    let acceptedTypes: [UTType]
    @Binding var data: Data?
    @Binding var fileExt: String?

    @State private var showPicker  = false
    @State private var isTargeted  = false

    var body: some View {
        if data != nil {
            attachedRow
        } else {
            emptyRow
        }
    }

    // Shows the attached file label + remove button
    private var attachedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text((fileExt?.uppercased() ?? kindLabel) + " attached")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                data    = nil
                fileExt = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // Drop zone / select button
    private var emptyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text("Drop \(kindLabel) or")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Select…") { showPicker = true }
                .font(.caption)
                .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: acceptedTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            data    = try? Data(contentsOf: url)
            fileExt = url.pathExtension.lowercased()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let d = item as? Data, let url = URL(dataRepresentation: d, relativeTo: nil) else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let bytes = try? Data(contentsOf: url)
            let ext   = url.pathExtension.lowercased()
            DispatchQueue.main.async { data = bytes; fileExt = ext }
        }
        return true
    }
}

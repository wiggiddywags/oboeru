import SwiftUI
import AppKit

struct CardFrontView: View {

    let card: OboerCard
    let onShowAnswer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    cardTypeTag

                    // Video (takes priority over image if both present)
                    if let data = card.frontVideoData {
                        CardVideoPlayerView(data: data, fileExtension: card.frontVideoExt ?? "mp4")
                            .padding(.horizontal, 32)
                    } else if let data = card.frontImageData {
                        SmartImageView(data: data, maxHeight: 280)
                            .padding(.horizontal, 32)
                    }

                    if let rtf = card.frontRTFData {
                        RichTextDisplayView(rtfData: rtf, centered: true)
                            .frame(minHeight: 40)
                            .padding(.horizontal, 32)
                    } else {
                        Text(card.displayFront)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding(.horizontal, 32)
                    }

                    // Audio player
                    if let data = card.frontAudioData {
                        CardAudioPlayerView(data: data)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }

            Divider()

            // Answer input field
            AnswerInputField(onSubmit: onShowAnswer)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            Button(action: onShowAnswer) {
                Text("Show Answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var cardTypeTag: some View {
        Text(card.cardType == .cloze ? "Cloze" : "Basic")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Answer input field

/// A plain multiline text field for typing the answer.
/// • Enter alone  → calls onSubmit (shows answer)
/// • Shift+Enter  → inserts a newline
struct AnswerInputField: NSViewRepresentable {

    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSubmit: onSubmit) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.isRichText = false
        tv.allowsUndo = true
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.delegate = context.coordinator
        context.coordinator.textView = tv

        // Placeholder-style prompt
        tv.insertionPointColor = .controlAccentColor

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        // Minimal border
        scrollView.wantsLayer = true
        scrollView.layer?.cornerRadius = 7
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Update border color on appearance change
        scrollView.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onSubmit: () -> Void
        weak var textView: NSTextView?

        init(onSubmit: @escaping () -> Void) { self.onSubmit = onSubmit }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Enter without modifiers → show answer
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let event = NSApp.currentEvent
                let shiftDown = event?.modifierFlags.contains(.shift) ?? false
                if !shiftDown {
                    onSubmit()
                    return true   // consumed
                }
                // Shift+Enter → insert a literal newline
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            return false
        }
    }
}

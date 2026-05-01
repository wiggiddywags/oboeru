import SwiftUI
import AppKit

struct CardFrontView: View {

    let card: OboerCard
    @Binding var typedAnswer: String
    let answerInputEnabled: Bool
    let onShowAnswer: () -> Void

    private var deckColor: Color {
        Color(hex: card.deck?.colorHex ?? "#5E9CF0") ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Card content ──────────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    // Deck color accent bar
                    deckColor
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                        .padding(.bottom, 32)

                    VStack(spacing: 20) {
                        cardTypeTag

                        // Media (video > image)
                        if let data = card.frontVideoData {
                            CardVideoPlayerView(data: data, fileExtension: card.frontVideoExt ?? "mp4")
                                .padding(.horizontal, 40)
                        } else if let data = card.frontImageData {
                            SmartImageView(data: data, maxHeight: 260)
                                .padding(.horizontal, 40)
                        }

                        // Sketch
                        if let data = card.frontSketchData {
                            SketchDisplayView(data: data)
                                .padding(.horizontal, 40)
                        }

                        // Question text
                        if let rtf = card.frontRTFData {
                            RichTextDisplayView(rtfData: rtf, centered: true)
                                .frame(minHeight: 40)
                                .padding(.horizontal, 40)
                        } else {
                            Text(card.displayFront)
                                .font(.custom("Georgia", size: 22))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                                .padding(.horizontal, 40)
                        }

                        // Audio
                        if let data = card.frontAudioData {
                            CardAudioPlayerView(data: data)
                                .padding(.horizontal, 40)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity)
            }

            // ── Bottom bar ────────────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider()

                if answerInputEnabled {
                    // Answer input field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your answer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)

                        AnswerInputField(text: $typedAnswer, onSubmit: onShowAnswer)
                            .frame(height: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.separator, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 12)

                    Divider()
                }

                // Show Answer button
                Button(action: onShowAnswer) {
                    HStack {
                        Text("Show Answer")
                            .font(.system(size: 15, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(deckColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private var cardTypeTag: some View {
        Text(card.cardType == .cloze ? "Cloze" : "Basic")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(deckColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(deckColor.opacity(0.10), in: Capsule())
    }
}

// MARK: - Answer input field (NSTextView wrapper)

struct AnswerInputField: NSViewRepresentable {

    @Binding var text: String
    let onSubmit: () -> Void
    var placeholder: String = "Type your answer…"

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.isRichText    = false
        tv.allowsUndo    = true
        tv.isEditable    = true
        tv.isSelectable  = true
        tv.drawsBackground = false
        tv.font          = .systemFont(ofSize: 14)
        tv.textColor     = .labelColor
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.delegate      = context.coordinator
        context.coordinator.textView = tv
        tv.insertionPointColor = .controlAccentColor

        scrollView.drawsBackground   = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Sync external clears (e.g., after rating a card)
        if tv.string != text {
            tv.string = text
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AnswerInputField
        weak var textView: NSTextView?

        init(parent: AnswerInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let shiftDown = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                if !shiftDown {
                    parent.onSubmit()
                    return true
                }
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            return false
        }
    }
}

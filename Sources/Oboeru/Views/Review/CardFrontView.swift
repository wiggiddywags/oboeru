import SwiftUI
import AppKit

private let answerPlaceholders: [String] = [
    "What do you recall?",
    "Type your answer…",
    "Test your memory…",
    "Can you remember?",
    "Write it down…",
    "Think, then type…",
    "What comes to mind?",
    "Take your best guess…",
    "Recall and type…",
    "Your answer here…",
]

struct CardFrontView: View {

    let card: OboerCard
    @Binding var typedAnswer: String
    let answerInputEnabled: Bool
    let onShowAnswer: () -> Void

    @State private var placeholder: String = answerPlaceholders.randomElement()!

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
                            Text(card.effectiveFront)
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

                        // ── Answer input (inside the card, prominent) ──────────
                        if answerInputEnabled {
                            answerInputSection
                                .padding(.horizontal, 40)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity)
            }
            .animation(.easeInOut(duration: 0.18), value: answerInputEnabled)

            // ── Show Answer button ─────────────────────────────────────────────
            VStack(spacing: 0) {
                Divider()
                Button(action: onShowAnswer) {
                    HStack(spacing: 8) {
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
        .onAppear {
            placeholder = answerPlaceholders.randomElement()!
        }
    }

    // MARK: - Answer input section

    private var answerInputSection: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(deckColor)
                Text("Your answer")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(deckColor)
                Spacer()
                Text("↵ to reveal")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                AnswerInputField(text: $typedAnswer, placeholder: placeholder, onSubmit: onShowAnswer)
                    .frame(height: 88)

                if typedAnswer.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 13)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(deckColor.opacity(0.40), lineWidth: 1.5)
            )
            .background(
                deckColor.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .padding(16)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(deckColor.opacity(0.15), lineWidth: 1)
        )
    }

    private var cardTypeTag: some View {
        HStack(spacing: 6) {
            Text(card.cardType == .cloze ? "Cloze" : "Basic")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(deckColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(deckColor.opacity(0.10), in: Capsule())

            if card.isReversed {
                Text("Reversed")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10), in: Capsule())
            }
        }
    }
}

// MARK: - Answer input field (NSTextView wrapper)

struct AnswerInputField: NSViewRepresentable {

    @Binding var text: String
    var placeholder: String = "Type your answer…"
    let onSubmit: () -> Void

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

        scrollView.drawsBackground    = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
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

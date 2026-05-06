import SwiftUI

struct CardBackView: View {

    let card: OboerCard
    var typedAnswer: String = ""

    private var deckColor: Color {
        Color(hex: card.deck?.colorHex ?? "#5E9CF0") ?? .accentColor
    }

    // Simple match: case-insensitive, whitespace-trimmed
    private var answerWasTyped: Bool { !typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var answeredCorrectly: Bool {
        let typed   = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = card.effectiveBack.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !typed.isEmpty && !correct.isEmpty && typed == correct
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Deck accent bar ────────────────────────────────────────
                deckColor
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
                    .padding(.bottom, 24)

                VStack(spacing: 24) {

                    // ── Front echo (question, dimmed) ──────────────────────
                    Group {
                        if let rtf = card.effectiveFrontRTF {
                            RichTextDisplayView(rtfData: rtf, centered: true)
                                .frame(minHeight: 24)
                                .opacity(0.45)
                        } else {
                            Text(card.effectiveFront)
                                .font(.custom("Georgia", size: 15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                        }
                    }
                    .padding(.horizontal, 40)

                    // ── Decorative divider ────────────────────────────────
                    answerDivider

                    // ── Back media (video > image > sketch) ───────────────
                    if let data = card.backVideoData {
                        CardVideoPlayerView(data: data, fileExtension: card.backVideoExt ?? "mp4")
                            .padding(.horizontal, 40)
                    } else if let data = card.backImageData {
                        SmartImageView(data: data, maxHeight: 260)
                            .padding(.horizontal, 40)
                    }

                    if let data = card.backSketchData {
                        SketchDisplayView(data: data)
                            .padding(.horizontal, 40)
                    }

                    // ── Answer text ────────────────────────────────────────
                    if let rtf = card.effectiveBackRTF {
                        RichTextDisplayView(rtfData: rtf, centered: true)
                            .frame(minHeight: 40)
                            .padding(.horizontal, 40)
                    } else {
                        Text(card.effectiveBack)
                            .font(.custom("Georgia", size: 26))
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 40)
                    }

                    // ── Audio ──────────────────────────────────────────────
                    if let data = card.backAudioData {
                        CardAudioPlayerView(data: data)
                            .padding(.horizontal, 40)
                    }

                    // ── Answer comparison ──────────────────────────────────
                    if answerWasTyped {
                        answerComparisonView
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Decorative divider

    private var answerDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
            Text("Answer")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Answer comparison

    @ViewBuilder
    private var answerComparisonView: some View {
        let correct  = answeredCorrectly
        let accent   = correct ? Color.green : Color.red

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(accent)
                Text(correct ? "Correct!" : "Your answer")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(accent)
                Spacer()
            }

            if !correct {
                Text(typedAnswer)
                    .font(.custom("Georgia", size: 15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(accent.opacity(0.25), lineWidth: 1)
                    )
            }
        }
        .padding(14)
        .background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

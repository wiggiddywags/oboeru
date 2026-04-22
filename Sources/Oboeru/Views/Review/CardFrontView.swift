import SwiftUI

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

            Button(action: onShowAnswer) {
                Text("Show Answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.space, modifiers: [])
            .padding(16)
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

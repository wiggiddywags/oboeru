import SwiftUI

struct CardBackView: View {

    let card: OboerCard

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // ── Front (dimmed) ──
                Text(card.displayFront)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 32)

                Divider().padding(.horizontal, 64)

                // ── Back (answer) ──
                VStack(spacing: 16) {

                    // Video takes priority over image when both are present
                    if let data = card.backVideoData {
                        CardVideoPlayerView(data: data, fileExtension: card.backVideoExt ?? "mp4")
                            .padding(.horizontal, 32)
                    } else if let data = card.backImageData {
                        SmartImageView(data: data, maxHeight: 280)
                            .padding(.horizontal, 32)
                    }

                    Text(card.displayBack)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 32)

                    if let data = card.backAudioData {
                        CardAudioPlayerView(data: data)
                            .padding(.horizontal, 32)
                    }
                }
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

import SwiftUI

struct CardFrontView: View {

    let card: OboerCard
    let onShowAnswer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    cardTypeTag

                    // Front image (if present)
                    if let data = card.frontImageData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 32)
                    }

                    Text(card.displayFront)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 32)
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

import SwiftUI

struct CardBackView: View {

    let card: OboerCard

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Front (dimmed)
                Text(card.displayFront)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 32)

                Divider()
                    .padding(.horizontal, 64)

                // Back (answer)
                Text(card.displayBack)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .padding(.horizontal, 32)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

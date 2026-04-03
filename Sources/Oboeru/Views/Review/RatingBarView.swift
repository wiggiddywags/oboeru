import SwiftUI
import FSRS

struct RatingBarView: View {

    let previews: StudySession.RatingPreviews
    let onRate: (Rating) -> Void

    var body: some View {
        HStack(spacing: 12) {
            RatingButton(
                label: "Again",
                interval: previews.again.intervalLabel,
                color: .red,
                key: "1",
                action: { onRate(.again) }
            )
            RatingButton(
                label: "Hard",
                interval: previews.hard.intervalLabel,
                color: .orange,
                key: "2",
                action: { onRate(.hard) }
            )
            RatingButton(
                label: "Good",
                interval: previews.good.intervalLabel,
                color: .green,
                key: "3",
                action: { onRate(.good) }
            )
            RatingButton(
                label: "Easy",
                interval: previews.easy.intervalLabel,
                color: .blue,
                key: "4",
                action: { onRate(.easy) }
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

private struct RatingButton: View {
    let label: String
    let interval: String
    let color: Color
    let key: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(interval)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
    }
}

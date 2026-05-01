import SwiftUI

struct RatingBarView: View {

    let previews: FSRSPreviews
    let onRate: (OboerRating) -> Void

    var body: some View {
        HStack(spacing: 10) {
            RatingButton(label: "Again", interval: previews.again.intervalLabel, color: .red,    key: "1") { onRate(.again) }
            RatingButton(label: "Hard",  interval: previews.hard.intervalLabel,  color: .orange, key: "2") { onRate(.hard)  }
            RatingButton(label: "Good",  interval: previews.good.intervalLabel,  color: .green,  key: "3") { onRate(.good)  }
            RatingButton(label: "Easy",  interval: previews.easy.intervalLabel,  color: .blue,   key: "4") { onRate(.easy)  }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct RatingButton: View {
    let label:    String
    let interval: String
    let color:    Color
    let key:      String
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(interval)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.80))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(color, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [])
    }
}

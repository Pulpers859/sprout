import SwiftUI

struct SuccessToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .background(Color.sageDark.opacity(0.85), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}

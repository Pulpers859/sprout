import UIKit

enum HapticFeedback {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

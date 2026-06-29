import SwiftUI
import UIKit

private func adaptive(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

extension Color {
    static let sproutBackground = adaptive(
        light: UIColor(red: 0.957, green: 0.969, blue: 0.959, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.098, blue: 0.086, alpha: 1)
    )
    static let sproutCard = adaptive(
        light: .white,
        dark: UIColor(red: 0.125, green: 0.149, blue: 0.133, alpha: 1)
    )
    static let sproutCardSoft = adaptive(
        light: UIColor(red: 0.925, green: 0.945, blue: 0.930, alpha: 1),
        dark: UIColor(red: 0.098, green: 0.122, blue: 0.106, alpha: 1)
    )
    static let sproutText = adaptive(
        light: UIColor(red: 0.071, green: 0.122, blue: 0.094, alpha: 1),
        dark: UIColor(red: 0.910, green: 0.933, blue: 0.918, alpha: 1)
    )
    static let sproutTextSecondary = adaptive(
        light: UIColor(red: 0.259, green: 0.333, blue: 0.290, alpha: 1),
        dark: UIColor(red: 0.690, green: 0.745, blue: 0.706, alpha: 1)
    )
    static let sproutTextMuted = adaptive(
        light: UIColor(red: 0.420, green: 0.486, blue: 0.447, alpha: 1),
        dark: UIColor(red: 0.475, green: 0.537, blue: 0.498, alpha: 1)
    )
    static let sage = adaptive(
        light: UIColor(red: 0.102, green: 0.580, blue: 0.459, alpha: 1),
        dark: UIColor(red: 0.149, green: 0.659, blue: 0.525, alpha: 1)
    )
    static let sageDark = adaptive(
        light: UIColor(red: 0.035, green: 0.337, blue: 0.286, alpha: 1),
        dark: UIColor(red: 0.118, green: 0.533, blue: 0.439, alpha: 1)
    )
    static let sageLight = adaptive(
        light: UIColor(red: 0.855, green: 0.933, blue: 0.882, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.165, blue: 0.122, alpha: 1)
    )
    static let sageMist = adaptive(
        light: UIColor(red: 0.914, green: 0.961, blue: 0.928, alpha: 1),
        dark: UIColor(red: 0.067, green: 0.133, blue: 0.098, alpha: 1)
    )
    static let sproutBlue = adaptive(
        light: UIColor(red: 0.235, green: 0.420, blue: 0.788, alpha: 1),
        dark: UIColor(red: 0.337, green: 0.518, blue: 0.878, alpha: 1)
    )
    static let sproutBlueLight = adaptive(
        light: UIColor(red: 0.875, green: 0.918, blue: 0.970, alpha: 1),
        dark: UIColor(red: 0.098, green: 0.137, blue: 0.220, alpha: 1)
    )
    static let sproutAmber = adaptive(
        light: UIColor(red: 0.824, green: 0.584, blue: 0.180, alpha: 1),
        dark: UIColor(red: 0.890, green: 0.659, blue: 0.275, alpha: 1)
    )
    static let sproutRed = adaptive(
        light: UIColor(red: 0.773, green: 0.251, blue: 0.259, alpha: 1),
        dark: UIColor(red: 0.859, green: 0.365, blue: 0.373, alpha: 1)
    )
    static let sproutRedLight = adaptive(
        light: UIColor(red: 0.984, green: 0.902, blue: 0.902, alpha: 1),
        dark: UIColor(red: 0.200, green: 0.098, blue: 0.098, alpha: 1)
    )
    static let sproutMint = adaptive(
        light: UIColor(red: 0.431, green: 0.945, blue: 0.737, alpha: 1),
        dark: UIColor(red: 0.306, green: 0.816, blue: 0.612, alpha: 1)
    )
    static let sproutAmberBright = adaptive(
        light: UIColor(red: 1.000, green: 0.761, blue: 0.286, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.714, blue: 0.231, alpha: 1)
    )
    static let sproutRedBright = adaptive(
        light: UIColor(red: 1.000, green: 0.431, blue: 0.431, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.388, blue: 0.388, alpha: 1)
    )
    static let sproutPace = adaptive(
        light: UIColor(white: 1.0, alpha: 0.55),
        dark: UIColor(white: 1.0, alpha: 0.35)
    )
    static let sproutBorder = adaptive(
        light: UIColor(red: 0.835, green: 0.875, blue: 0.847, alpha: 1),
        dark: UIColor(red: 0.176, green: 0.212, blue: 0.188, alpha: 1)
    )
    static let sproutBorderDark = adaptive(
        light: UIColor(red: 0.690, green: 0.757, blue: 0.710, alpha: 1),
        dark: UIColor(red: 0.255, green: 0.306, blue: 0.271, alpha: 1)
    )
    static let sproutChip = adaptive(
        light: UIColor(red: 0.910, green: 0.941, blue: 0.918, alpha: 1),
        dark: UIColor(red: 0.118, green: 0.153, blue: 0.129, alpha: 1)
    )
    static let sproutTrack = adaptive(
        light: UIColor(red: 0.839, green: 0.878, blue: 0.851, alpha: 1),
        dark: UIColor(red: 0.176, green: 0.212, blue: 0.188, alpha: 1)
    )
    static let sproutShadow = adaptive(
        light: UIColor(white: 0, alpha: 0.07),
        dark: UIColor(white: 0, alpha: 0.30)
    )
}

extension BudgetTab {
    var accentColor: Color {
        switch self {
        case .personal:
            .sage
        case .grocery:
            .sproutBlue
        }
    }

    var accentDarkColor: Color {
        switch self {
        case .personal:
            .sageDark
        case .grocery:
            adaptive(
                light: UIColor(red: 0.102, green: 0.204, blue: 0.510, alpha: 1),
                dark: UIColor(red: 0.275, green: 0.443, blue: 0.816, alpha: 1)
            )
        }
    }

    var accentLightColor: Color {
        switch self {
        case .personal:
            .sageLight
        case .grocery:
            .sproutBlueLight
        }
    }

    var heroGradient: LinearGradient {
        switch self {
        case .personal:
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.369, blue: 0.318),
                    Color(red: 0.047, green: 0.475, blue: 0.396)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .grocery:
            LinearGradient(
                colors: [
                    Color(red: 0.110, green: 0.235, blue: 0.565),
                    Color(red: 0.216, green: 0.365, blue: 0.745)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

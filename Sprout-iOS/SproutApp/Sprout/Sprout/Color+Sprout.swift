import SwiftUI

extension Color {
    static let sproutBackground = Color(red: 0.957, green: 0.969, blue: 0.959)
    static let sproutCard = Color.white
    static let sproutCardSoft = Color(red: 0.925, green: 0.945, blue: 0.930)
    static let sproutText = Color(red: 0.071, green: 0.122, blue: 0.094)
    static let sproutTextSecondary = Color(red: 0.259, green: 0.333, blue: 0.290)
    static let sproutTextMuted = Color(red: 0.420, green: 0.486, blue: 0.447)
    static let sage = Color(red: 0.102, green: 0.580, blue: 0.459)
    static let sageDark = Color(red: 0.035, green: 0.337, blue: 0.286)
    static let sageLight = Color(red: 0.855, green: 0.933, blue: 0.882)
    static let sageMist = Color(red: 0.914, green: 0.961, blue: 0.928)
    static let sproutBlue = Color(red: 0.235, green: 0.420, blue: 0.788)
    static let sproutBlueLight = Color(red: 0.875, green: 0.918, blue: 0.970)
    static let sproutAmber = Color(red: 0.824, green: 0.584, blue: 0.180)
    static let sproutRed = Color(red: 0.773, green: 0.251, blue: 0.259)
    static let sproutRedLight = Color(red: 0.984, green: 0.902, blue: 0.902)
    static let sproutMint = Color(red: 0.431, green: 0.945, blue: 0.737)
    static let sproutAmberBright = Color(red: 1.000, green: 0.761, blue: 0.286)
    static let sproutRedBright = Color(red: 1.000, green: 0.431, blue: 0.431)
    static let sproutPace = Color.white.opacity(0.55)
    static let sproutBorder = Color(red: 0.835, green: 0.875, blue: 0.847)
    static let sproutBorderDark = Color(red: 0.690, green: 0.757, blue: 0.710)
    static let sproutChip = Color(red: 0.910, green: 0.941, blue: 0.918)
    static let sproutTrack = Color(red: 0.839, green: 0.878, blue: 0.851)
    static let sproutShadow = Color.black.opacity(0.07)
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
            Color(red: 0.102, green: 0.204, blue: 0.510)
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

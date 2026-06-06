import SwiftUI

extension Color {
    static let sproutBackground = Color(red: 0.957, green: 0.969, blue: 0.959)
    static let sproutCard = Color.white
    static let sproutCardSoft = Color(red: 0.925, green: 0.945, blue: 0.930)
    static let sproutText = Color(red: 0.071, green: 0.122, blue: 0.094)
    static let sproutTextSecondary = Color(red: 0.259, green: 0.333, blue: 0.290)
    static let sproutTextMuted = Color(red: 0.420, green: 0.486, blue: 0.447)
    static let sage = Color(red: 0.216, green: 0.529, blue: 0.376)
    static let sageDark = Color(red: 0.102, green: 0.337, blue: 0.235)
    static let sageLight = Color(red: 0.855, green: 0.933, blue: 0.882)
    static let sageMist = Color(red: 0.914, green: 0.961, blue: 0.928)
    static let sproutBlue = Color(red: 0.216, green: 0.431, blue: 0.678)
    static let sproutBlueLight = Color(red: 0.875, green: 0.918, blue: 0.970)
    static let sproutAmber = Color(red: 0.824, green: 0.584, blue: 0.180)
    static let sproutRed = Color(red: 0.773, green: 0.251, blue: 0.259)
    static let sproutRedLight = Color(red: 0.984, green: 0.902, blue: 0.902)
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
            Color(red: 0.122, green: 0.286, blue: 0.506)
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
}

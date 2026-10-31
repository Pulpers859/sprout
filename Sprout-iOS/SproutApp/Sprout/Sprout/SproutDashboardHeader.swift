import SwiftUI

/// The app title plus the settings and overflow buttons.
///
/// Shared by the budget dashboard and the holiday dashboard. Duplicating it
/// would have given the two tabs headers that drifted apart in spacing, touch
/// target size, and accessibility labels.
struct SproutDashboardHeader<MenuContent: View>: View {
    let onOpenSettings: () -> Void
    @ViewBuilder let menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 10) {
            Text("Sprout")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.sproutText)

            Spacer()

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .frame(width: 44, height: 44)
                    .background(Color.sproutCard, in: Circle())
                    .overlay(Circle().stroke(Color.sproutBorderDark, lineWidth: 1))
                    .shadow(color: Color.sproutShadow, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Menu {
                menuContent()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.sproutText)
                    .frame(width: 44, height: 44)
                    .background(Color.sproutCard, in: Circle())
                    .overlay(Circle().stroke(Color.sproutBorderDark, lineWidth: 1))
                    .shadow(color: Color.sproutShadow, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .frame(minHeight: 44)
    }
}

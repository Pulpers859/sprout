import SwiftUI

struct BottomTabBarView: View {
    @Binding var selection: BudgetTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BudgetTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Text(tab.icon)
                            .font(.title3)
                        Text(tab.shortTitle)
                            .font(.caption.weight(selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Color.sageDark : Color.sproutTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(selection == tab ? Color.sageMist : .clear)
                    )
                }
                .buttonStyle(.plain)
                .opacity(selection == tab ? 1 : 0.78)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.sproutCard.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.sproutBorder, lineWidth: 1)
        )
        .shadow(color: Color.sproutShadow, radius: 18, x: 0, y: 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

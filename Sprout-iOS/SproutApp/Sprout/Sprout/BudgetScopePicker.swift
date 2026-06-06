import SwiftUI

struct BudgetScopePicker: View {
    @Binding var selection: BudgetTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(BudgetTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab == .personal ? "person.fill" : "cart.fill")
                            .font(.caption.weight(.semibold))
                        Text(tab.shortTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selection == tab ? Color.white : Color.sproutTextSecondary)
                    .background(
                        Capsule()
                            .fill(selection == tab ? tab.accentDarkColor : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.sproutCard, in: Capsule())
        .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
    }
}

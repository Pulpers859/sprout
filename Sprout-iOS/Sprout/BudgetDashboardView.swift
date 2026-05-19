import SwiftUI

struct BudgetDashboardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void
    let onRequestDeleteTransaction: (TransactionEntry) -> Void
    let onOpenTransaction: (TransactionMode, TransactionEntry?) -> Void

    @State private var isShowingCalendar = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SummaryCardView(tab: tab, onEditBudget: onEditBudget)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingCalendar.toggle()
                        if !isShowingCalendar {
                            store.selectedCalendarDate = nil
                        }
                    }
                } label: {
                    Label(isShowingCalendar ? "Hide calendar" : "View calendar", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isShowingCalendar ? Color.sageDark : Color.sproutTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(isShowingCalendar ? Color.sageLight : Color.sproutCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isShowingCalendar ? Color.sage : Color.sproutBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                if isShowingCalendar {
                    CalendarCardView(tab: tab)
                }

                if !store.recentTransactions(for: tab).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Add")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sproutTextMuted)
                            .textCase(.uppercase)

                        FlowLayout(spacing: 8) {
                            ForEach(store.recentTransactions(for: tab)) { entry in
                                Button {
                                    onOpenTransaction(.expense, entry)
                                } label: {
                                    Text("\(entry.emoji) \(entry.name)")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.sproutText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(Capsule().fill(Color.sproutCard))
                                        .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        onOpenTransaction(.expense, nil)
                    } label: {
                        QuickActionButtonLabel(title: "Add expense", symbol: "plus")
                    }

                    Button {
                        onOpenTransaction(.payment, nil)
                    } label: {
                        QuickActionButtonLabel(title: "Add payment", symbol: "arrow.uturn.backward")
                    }
                }
                .buttonStyle(.plain)

                transactionsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(Color.sproutBackground.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tab.title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .foregroundStyle(Color.sproutText)

                    Text(store.currentMonthLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transactions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.sproutTextMuted)
                .textCase(.uppercase)

            let transactions = store.transactions(for: tab)

            if transactions.isEmpty {
                Text(tab.emptyStateMessage)
                    .font(.body)
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 36)
            } else {
                ForEach(transactions, id: \.id) { entry in
                    TransactionRowView(entry: entry) {
                        onRequestDeleteTransaction(entry)
                    }
                }
            }
        }
    }
}

private struct QuickActionButtonLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.sproutCard.opacity(0.22))
                    .frame(width: 32, height: 32)

                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
            }

            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.sageDark, Color.sage],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .shadow(color: Color.sageDark.opacity(0.18), radius: 12, x: 0, y: 8)
    }
}

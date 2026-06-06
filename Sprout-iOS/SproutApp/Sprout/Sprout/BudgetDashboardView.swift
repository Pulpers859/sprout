import SwiftUI

struct BudgetDashboardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void
    let onOpenSettings: () -> Void
    let onStartNewMonth: () -> Void
    let onRequestDeleteTransaction: (TransactionEntry) -> Void
    let onOpenTransaction: (TransactionMode, TransactionEntry?) -> Void

    @State private var isShowingCalendar = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                dashboardHeader

                BudgetScopePicker(selection: $store.activeTab)

                SummaryCardView(tab: tab, onEditBudget: onEditBudget)

                primaryActions

                quickAddSection

                monthActivitySection

                transactionsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Color.sproutBackground.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: tab)
    }

    private var dashboardHeader: some View {
        HStack(spacing: 10) {
            Text("Sprout")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.sproutText)

            Spacer()

            Button {
                onOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .tint(Color.sproutCard)
            .accessibilityLabel("Settings")

            Menu {
                Button("Start a new month", systemImage: "arrow.counterclockwise") {
                    onStartNewMonth()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .tint(Color.sproutCard)
            .accessibilityLabel("More")
        }
        .frame(minHeight: 44)
    }

    private var primaryActions: some View {
        HStack(spacing: 12) {
            Button {
                onOpenTransaction(.expense, nil)
            } label: {
                Label("Add expense", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(tab.accentDarkColor)

            Button {
                onOpenTransaction(.payment, nil)
            } label: {
                Label("Payment", systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .tint(tab.accentColor)
        }
    }

    @ViewBuilder
    private var quickAddSection: some View {
        let recent = store.recentTransactions(for: tab)

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Repeat", detail: "Recent purchases")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(recent) { entry in
                            Button {
                                onOpenTransaction(.expense, entry)
                            } label: {
                                HStack(spacing: 7) {
                                    Text(entry.emoji)
                                    Text(entry.name)
                                        .lineLimit(1)
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.sproutText)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 10)
                                .background(Color.sproutCard, in: Capsule())
                                .overlay(Capsule().stroke(Color.sproutBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 1, for: .scrollContent)
            }
        }
    }

    private var monthActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.3)) {
                    isShowingCalendar.toggle()
                    if !isShowingCalendar {
                        store.selectedCalendarDate = nil
                    }
                }
            } label: {
                HStack {
                    sectionHeader("This month", detail: store.currentMonthLabel)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.sproutTextMuted)
                        .rotationEffect(.degrees(isShowingCalendar ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isShowingCalendar {
                CalendarCardView(tab: tab)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var transactionsSection: some View {
        let transactions = store.transactions(for: tab)

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Transactions", detail: "\(transactions.count)")
                .padding(.bottom, 8)

            if transactions.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add your first \(tab.shortTitle.lowercased()) expense to start tracking this month.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(Array(transactions.enumerated()), id: \.element.id) { index, entry in
                    TransactionRowView(entry: entry) {
                        onRequestDeleteTransaction(entry)
                    }

                    if index < transactions.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.sproutText)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.sproutTextMuted)
        }
    }
}

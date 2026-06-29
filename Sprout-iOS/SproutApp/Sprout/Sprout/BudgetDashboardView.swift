import SwiftUI

struct BudgetDashboardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab
    let onEditBudget: () -> Void
    let onOpenSettings: () -> Void
    let onStartNewMonth: () -> Void
    let onRequestDeleteTransaction: (TransactionEntry) -> Void
    let onEditTransaction: (TransactionEntry) -> Void
    let onOpenTransaction: (TransactionMode, TransactionEntry?) -> Void

    @State private var isShowingCalendar = false
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                dashboardHeader

                BudgetScopePicker(selection: $store.activeTab)

                SummaryCardView(tab: tab, onEditBudget: onEditBudget)

                if SproutDate.daysLeftInMonth() <= 3 {
                    Button {
                        onStartNewMonth()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Month ending soon")
                                    .font(.subheadline.weight(.semibold))
                                Text("Tap to start a new month and carry over your balance.")
                                    .font(.caption)
                                    .foregroundStyle(Color.sproutTextSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.sproutTextMuted)
                        }
                        .padding(14)
                        .background(tab.accentLightColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(tab.accentColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.sproutText)
                    .frame(width: 40, height: 40)
                    .background(Color.sproutCard, in: Circle())
                    .overlay(Circle().stroke(Color.sproutBorderDark, lineWidth: 1))
                    .shadow(color: Color.sproutShadow, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Menu {
                Button("Start a new month", systemImage: "arrow.counterclockwise") {
                    onStartNewMonth()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.sproutText)
                    .frame(width: 40, height: 40)
                    .background(Color.sproutCard, in: Circle())
                    .overlay(Circle().stroke(Color.sproutBorderDark, lineWidth: 1))
                    .shadow(color: Color.sproutShadow, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
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
        let allTransactions = store.transactions(for: tab)
        let filtered = searchText.isEmpty
            ? allTransactions
            : allTransactions.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.note.localizedCaseInsensitiveContains(searchText)
            }

        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Transactions", detail: "\(allTransactions.count)")
                .padding(.bottom, 8)

            if allTransactions.count >= 5 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.sproutTextMuted)
                    TextField("Search transactions", text: $searchText)
                        .font(.subheadline)
                        .foregroundStyle(Color.sproutText)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.sproutTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.sproutCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.sproutBorder, lineWidth: 1))
                .padding(.bottom, 10)
            }

            if allTransactions.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Add your first \(tab.shortTitle.lowercased()) expense to start tracking this month.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else if filtered.isEmpty {
                Text("No matching transactions")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                    TransactionRowView(entry: entry, onEdit: {
                        onEditTransaction(entry)
                    }, onRemove: {
                        onRequestDeleteTransaction(entry)
                    })

                    if index < filtered.count - 1 {
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

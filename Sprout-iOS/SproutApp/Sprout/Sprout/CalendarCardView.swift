import SwiftUI

struct CalendarCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = min(max(calendar.firstWeekday - 1, 0), symbols.count - 1)
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    var body: some View {
        let grouped = Dictionary(grouping: store.transactions(for: tab), by: { SproutDate.dayKey(for: $0.date) })

        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.sproutTextMuted)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(store.monthGridDates().enumerated()), id: \.offset) { item in
                    if let date = item.element {
                        dayCell(date: date, grouped: grouped)
                    } else {
                        Color.clear
                            .frame(height: 46)
                    }
                }
            }

            let outsideCount = store.transactionsOutsideDisplayedMonth(for: tab)
            if outsideCount > 0 {
                // These are in the totals and in the transaction list but have no
                // cell here, so the grid would otherwise look like it disagreed
                // with the summary card.
                Label(
                    "\(outsideCount) transaction\(outsideCount == 1 ? " is" : "s are") dated outside \(store.currentMonthLabel) and counted in the totals below.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(Color.sproutTextMuted)
            }

            if let selected = store.selectedCalendarDate {
                selectedDayDetail(selected, grouped: grouped)
            }
        }
        .padding(.vertical, 6)
    }

    private func netSpending(for entries: [TransactionEntry]) -> MoneyAmount {
        entries.reduce(.zero) { $0 + ($1.isRefund ? -$1.amount : $1.amount) }
    }

    @ViewBuilder
    private func dayCell(date: Date, grouped: [String: [TransactionEntry]]) -> some View {
        let key = SproutDate.dayKey(for: date)
        let entries = grouped[key] ?? []
        let net = netSpending(for: entries)
        let isSelected = store.selectedCalendarDate.map { SproutDate.dayKey(for: $0) == key } ?? false
        let isToday = Calendar.current.isDateInToday(date)

        Button {
            if isSelected {
                store.selectedCalendarDate = nil
            } else {
                store.selectedCalendarDate = date
            }
        } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.sproutAmber : Color.sproutText)

                if !entries.isEmpty {
                    Text("\(net < .zero ? "+" : "")\(SproutFormatters.compactCurrency(net.magnitude))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(net < .zero ? Color.sageDark : Color.sproutTextSecondary)
                        // A cell is ~46pt wide; an amount with a cents tail needs to
                        // shrink rather than truncate mid-figure.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tab.accentLightColor : (entries.isEmpty ? .clear : Color.sproutChip))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? tab.accentColor : (isToday ? Color.sproutAmber : .clear), lineWidth: isSelected || isToday ? 2 : 0)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(.dateTime.day(.defaultDigits).month(.wide)))\(entries.isEmpty ? "" : ", \(SproutFormatters.currency(net.magnitude)) \(net < .zero ? "refunded" : "spent")")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func selectedDayDetail(_ date: Date, grouped: [String: [TransactionEntry]]) -> some View {
        let entries = grouped[SproutDate.dayKey(for: date)] ?? []

        VStack(alignment: .leading, spacing: 10) {
            Text(SproutDate.fullDay(date))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.sproutTextSecondary)

            if entries.isEmpty {
                Text("No transactions this day")
                    .font(.subheadline)
                    .foregroundStyle(Color.sproutTextMuted)
                    .italic()
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top) {
                        Text("\(entry.isRefund ? "💸" : entry.emoji) \(entry.name)")
                            .foregroundStyle(Color.sproutText)

                        Spacer()

                        Text("\(entry.isRefund ? "+" : "−")\(SproutFormatters.currency(entry.amount))")
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                            .foregroundStyle(entry.isRefund ? Color.sageDark : Color.sproutText)
                    }

                    if !entry.note.isEmpty {
                        Text(entry.note)
                            .font(.footnote)
                            .foregroundStyle(Color.sproutTextMuted)
                    }
                }

                let net = netSpending(for: entries)

                HStack {
                    Spacer()
                    Text("Net: \(SproutFormatters.currency(net))")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(net > .zero ? Color.sproutText : Color.sageDark)
                }
            }
        }
        .padding(.top, 4)
    }
}

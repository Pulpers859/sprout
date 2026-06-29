import SwiftUI

struct CalendarCardView: View {
    @EnvironmentObject private var store: BudgetStore

    let tab: BudgetTab

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let offset = Calendar.current.firstWeekday - 1
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

                ForEach(Array(SproutDate.monthGridDates().enumerated()), id: \.offset) { item in
                    if let date = item.element {
                        dayCell(date: date, grouped: grouped)
                    } else {
                        Color.clear
                            .frame(height: 46)
                    }
                }
            }

            if let selected = store.selectedCalendarDate {
                selectedDayDetail(selected, grouped: grouped)
            }
        }
        .padding(.vertical, 6)
    }

    private func netSpending(for entries: [TransactionEntry]) -> Double {
        entries.reduce(0) { $0 + ($1.isRefund ? -$1.amount : $1.amount) }
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
                    Text("\(net < 0 ? "+" : "")\(SproutFormatters.compactCurrency(abs(net)))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(net < 0 ? Color.sageDark : Color.sproutTextSecondary)
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
                        .foregroundStyle(net > 0 ? Color.sproutText : Color.sageDark)
                }
            }
        }
        .padding(.top, 4)
    }
}

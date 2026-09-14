import Foundation

enum SproutDate {
    static func currentMonthKey(now: Date = .now, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: now)
        let year = components.year ?? 0
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func monthYearTitle(date: Date = .now) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }

    static func firstDate(forMonthKey monthKey: String, calendar: Calendar = .current) -> Date? {
        let components = monthKey.split(separator: "-")
        guard
            components.count == 2,
            let year = Int(components[0]),
            let month = Int(components[1])
        else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    static func lastDate(forMonthKey monthKey: String, calendar: Calendar = .current) -> Date? {
        guard
            let firstDate = firstDate(forMonthKey: monthKey, calendar: calendar),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstDate),
            let lastDate = calendar.date(byAdding: .day, value: -1, to: nextMonth)
        else {
            return nil
        }

        return lastDate
    }

    /// Month keys are zero-padded `YYYY-MM`, so lexicographic order matches
    /// chronological order — relied on by the rollover walk.
    static func nextMonthKey(after monthKey: String, calendar: Calendar = .current) -> String? {
        guard
            let firstDate = firstDate(forMonthKey: monthKey, calendar: calendar),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstDate)
        else {
            return nil
        }

        return currentMonthKey(now: nextMonth, calendar: calendar)
    }

    static func monthYearTitle(forMonthKey monthKey: String, calendar: Calendar = .current) -> String {
        guard let date = firstDate(forMonthKey: monthKey, calendar: calendar) else {
            return monthKey
        }

        return monthYearTitle(date: date)
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func fullDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    static func daysLeftInMonth(now: Date = .now, calendar: Calendar = .current) -> Int {
        guard
            let range = calendar.range(of: .day, in: .month, for: now)
        else {
            return 1
        }

        let today = calendar.component(.day, from: now)
        return max(range.count - today + 1, 1)
    }

    static func monthPaceProgress(now: Date = .now, calendar: Calendar = .current) -> Double {
        guard let range = calendar.range(of: .day, in: .month, for: now) else {
            return 0
        }

        let today = calendar.component(.day, from: now)
        return min(max(Double(today) / Double(range.count), 0), 1)
    }

    /// The point inside `monthKey` that "now" corresponds to.
    ///
    /// Days-left and pace used to be read straight off the wall clock, so a stored
    /// month the user had not closed out yet (the reset prompt deferred, dismissed,
    /// or hidden behind a persistence alert) was measured against the *new* month:
    /// a September ledger showing October's day count and October's pace marker.
    /// Anchoring to the stored month keeps every derived figure describing the
    /// period the transactions actually belong to.
    ///
    /// - A stored month that is the live month anchors to `now`.
    /// - A past stored month anchors to its final day: the period is over.
    /// - A future stored month (device clock moved backwards) anchors to its first
    ///   day rather than pretending the month is spent.
    static func referenceDate(inMonthKey monthKey: String, now: Date = .now, calendar: Calendar = .current) -> Date {
        let liveKey = currentMonthKey(now: now, calendar: calendar)
        if monthKey == liveKey { return now }
        if monthKey < liveKey { return lastDate(forMonthKey: monthKey, calendar: calendar) ?? now }
        return firstDate(forMonthKey: monthKey, calendar: calendar) ?? now
    }

    static func daysLeft(inMonthKey monthKey: String, now: Date = .now, calendar: Calendar = .current) -> Int {
        daysLeftInMonth(
            now: referenceDate(inMonthKey: monthKey, now: now, calendar: calendar),
            calendar: calendar
        )
    }

    static func paceProgress(inMonthKey monthKey: String, now: Date = .now, calendar: Calendar = .current) -> Double {
        monthPaceProgress(
            now: referenceDate(inMonthKey: monthKey, now: now, calendar: calendar),
            calendar: calendar
        )
    }

    static func monthGridDates(forMonthKey monthKey: String, now: Date = .now, calendar: Calendar = .current) -> [Date?] {
        monthGridDates(
            for: firstDate(forMonthKey: monthKey, calendar: calendar) ?? now,
            calendar: calendar
        )
    }

    static func monthGridDates(for date: Date = .now, calendar: Calendar = .current) -> [Date?] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingEmptyDays = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        let padding = Array(repeating: Date?.none, count: leadingEmptyDays)
        let dates = (0 ..< dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: monthStart)
        }
        return padding + dates
    }
}

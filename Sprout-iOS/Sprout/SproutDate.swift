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

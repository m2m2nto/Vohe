import Foundation

enum LeitnerScheduler {
    /// Intervals in days, indexed by box.
    /// Index 0 is unseen/new (always due, has no interval).
    static let intervalsByBox: [Int] = [0, 1, 3, 7, 21, 60]

    static let maxBox = 5

    enum Grade { case again, good }

    /// Apply a grade and return the new (box, dueDate).
    /// Due dates are anchored to the local start-of-day so a card reviewed
    /// at 23:55 becomes due at 00:00 the next interval's day boundary.
    ///
    /// An unvalidated card (`isValidated == false`) is held at box 1 no matter
    /// how often it's graded Good, so an unconfirmed machine translation can't
    /// drift out to a 60-day interval before the user has looked at it.
    static func apply(
        grade: Grade,
        currentBox: Int,
        isValidated: Bool = true,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (box: Int, due: Date) {
        var newBox: Int
        switch grade {
        case .again:
            newBox = 1
        case .good:
            newBox = min(currentBox + 1, maxBox)
        }
        if !isValidated { newBox = min(newBox, 1) }
        let due = dueDate(from: now, intervalDays: intervalsByBox[newBox], calendar: calendar)
        return (newBox, due)
    }

    /// True when `nextDue` falls on or before the end of today (local).
    /// A box-0 card (`nextDue == .distantPast`) is always due.
    static func isDue(nextDue: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)
        return nextDue < tomorrowStart
    }

    private static func dueDate(from now: Date, intervalDays: Int, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: intervalDays, to: dayStart) ?? now
    }
}

import XCTest
@testable import Vohe

final class LeitnerSchedulerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h; comps.minute = min
        return calendar.date(from: comps)!
    }

    // Criterion 4: Good from box 2 → box 3, due = startOfDay(now) + 7d
    func testGoodFromBox2() {
        let now = date(2026, 5, 23, 12)
        let (box, due) = LeitnerScheduler.apply(grade: .good, currentBox: 2, now: now, calendar: calendar)
        XCTAssertEqual(box, 3)
        XCTAssertEqual(due, date(2026, 5, 30, 0, 0))
    }

    // Criterion 4: Good from box 5 caps at 5, due = startOfDay(now) + 60d
    func testGoodFromBox5DoesNotOverflow() {
        let now = date(2026, 5, 23, 12)
        let (box, due) = LeitnerScheduler.apply(grade: .good, currentBox: 5, now: now, calendar: calendar)
        XCTAssertEqual(box, 5)
        XCTAssertEqual(due, date(2026, 7, 22, 0, 0)) // 2026-05-23 + 60d
    }

    // Criterion 4: Good from box 0 (new) → box 1, due = +1d (not +0d)
    func testGoodFromNewCardGoesToBox1() {
        let now = date(2026, 5, 23, 12)
        let (box, due) = LeitnerScheduler.apply(grade: .good, currentBox: 0, now: now, calendar: calendar)
        XCTAssertEqual(box, 1)
        XCTAssertEqual(due, date(2026, 5, 24, 0, 0))
    }

    // Criterion 5: Again from any box → box 1, due = startOfDay(now) + 1d
    func testAgainResetsToBox1() {
        let now = date(2026, 5, 23, 12)
        for currentBox in 1...5 {
            let (box, due) = LeitnerScheduler.apply(grade: .again, currentBox: currentBox, now: now, calendar: calendar)
            XCTAssertEqual(box, 1, "from box \(currentBox)")
            XCTAssertEqual(due, date(2026, 5, 24, 0, 0), "from box \(currentBox)")
        }
    }

    // Criterion 15: Reviewing at 23:55 with +1d still produces midnight-of-tomorrow.
    func testTimezoneAnchorsToLocalStartOfDay() {
        let lateNight = date(2026, 5, 23, 23, 55)
        let (_, due) = LeitnerScheduler.apply(grade: .again, currentBox: 3, now: lateNight, calendar: calendar)
        XCTAssertEqual(due, date(2026, 5, 24, 0, 0))
    }

    // isDue helper sanity
    func testIsDue() {
        let now = date(2026, 5, 23, 12)
        XCTAssertTrue(LeitnerScheduler.isDue(nextDue: .distantPast, now: now, calendar: calendar))
        XCTAssertTrue(LeitnerScheduler.isDue(nextDue: date(2026, 5, 23, 23, 59), now: now, calendar: calendar))
        XCTAssertTrue(LeitnerScheduler.isDue(nextDue: date(2026, 5, 22, 0, 0), now: now, calendar: calendar))
        XCTAssertFalse(LeitnerScheduler.isDue(nextDue: date(2026, 5, 24, 0, 0), now: now, calendar: calendar))
    }
}

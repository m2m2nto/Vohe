import XCTest
import SwiftData
@testable import Vohe

@MainActor
final class SchedulerMigrationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    private let today = {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 23; comps.hour = 12
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c.date(from: comps)!
    }()

    override func setUp() async throws {
        let schema = Schema([Deck.self, Card.self, SessionResult.self, PausedSession.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    private func insertCard(deck: Deck, front: String, back: String) -> Card {
        let c = Card(front: front, back: back)
        c.deck = deck
        context.insert(c)
        return c
    }

    private func dayStart() -> Date { calendar.startOfDay(for: today) }

    // Criterion 2: bucket boundaries.
    func testBoxAssignmentByWrongRate() {
        let deck = Deck(name: "T", language1: "A", language2: "B")
        context.insert(deck)
        let easy = insertCard(deck: deck, front: "easy", back: "facile")     // 1/10 = 0.1 → box 3
        let mid = insertCard(deck: deck, front: "mid", back: "medio")        // 3/10 = 0.3 → box 2
        let hard = insertCard(deck: deck, front: "hard", back: "difficile")  // 5/10 = 0.5 → box 1
        let unseen = insertCard(deck: deck, front: "new", back: "nuovo")     // no stats → box 0
        let underSeen = insertCard(deck: deck, front: "us", back: "us-it")   // seen=2 → box 0
        let exactly20 = insertCard(deck: deck, front: "x20", back: "y20")    // 2/10 = 0.2 → box 2 (strict <)
        let exactly40 = insertCard(deck: deck, front: "x40", back: "y40")    // 4/10 = 0.4 → box 1 (strict <)

        let statsMap: [UUID: CardStats] = [
            easy.id:      CardStats(seen: 10, wrong: 1),
            mid.id:       CardStats(seen: 10, wrong: 3),
            hard.id:      CardStats(seen: 10, wrong: 5),
            underSeen.id: CardStats(seen: 2,  wrong: 0),
            exactly20.id: CardStats(seen: 10, wrong: 2),
            exactly40.id: CardStats(seen: 10, wrong: 4),
        ]

        SchedulerMigration.run(
            context: context,
            stats: { statsMap[$0.id] },
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(easy.boxIndex, 3)
        XCTAssertEqual(mid.boxIndex, 2)
        XCTAssertEqual(hard.boxIndex, 1)
        XCTAssertEqual(unseen.boxIndex, 0)
        XCTAssertEqual(unseen.nextDue, .distantPast)
        XCTAssertEqual(underSeen.boxIndex, 0)
        XCTAssertEqual(underSeen.nextDue, .distantPast)
        XCTAssertEqual(exactly20.boxIndex, 2)
        XCTAssertEqual(exactly40.boxIndex, 1)
    }

    // Criterion 3: due dates staggered evenly, no bucket > ceil(N/7).
    func testStaggeringDistribution() {
        let deck = Deck(name: "T", language1: "A", language2: "B")
        context.insert(deck)
        var cards: [Card] = []
        for i in 0..<50 {
            cards.append(insertCard(deck: deck, front: "w\(i)", back: "t\(i)"))
        }

        SchedulerMigration.run(
            context: context,
            stats: { _ in CardStats(seen: 10, wrong: 1) }, // all box 3
            today: today,
            calendar: calendar
        )

        let dueDates = cards.map(\.nextDue)
        let counts = Dictionary(grouping: dueDates, by: { $0 }).mapValues(\.count)
        let maxBucket = counts.values.max() ?? 0
        let expectedMax = Int(ceil(Double(cards.count) / Double(SchedulerMigration.staggerWindowDays)))
        XCTAssertLessThanOrEqual(maxBucket, expectedMax)

        // All due dates must lie within the next 7-day window starting at dayStart.
        for due in dueDates {
            XCTAssertGreaterThanOrEqual(due, dayStart())
            let limit = calendar.date(byAdding: .day, value: SchedulerMigration.staggerWindowDays, to: dayStart())!
            XCTAssertLessThan(due, limit)
        }
    }

    // Unassigned cards must never have a future nextDue set.
    func testUnseenStaysAtDistantPast() {
        let deck = Deck(name: "T", language1: "A", language2: "B")
        context.insert(deck)
        let c = insertCard(deck: deck, front: "x", back: "y")

        SchedulerMigration.run(
            context: context,
            stats: { _ in nil },
            today: today,
            calendar: calendar
        )

        XCTAssertEqual(c.boxIndex, 0)
        XCTAssertEqual(c.nextDue, .distantPast)
    }
}

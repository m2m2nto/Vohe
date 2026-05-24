import Foundation
import SwiftData

enum SchedulerMigration {
    static let userDefaultsKey = "vohe.schedulerBackfillCompleted.v1"
    static let staggerWindowDays = 7

    /// Walks every Card in `context`, assigning `boxIndex` and `nextDue` based on
    /// historical wrong-rate stats. Cards without enough history stay at box 0.
    /// Assigned cards (box ≥ 1) get `nextDue` staggered evenly across the next
    /// 7 days (round-robin over a shuffled list) to avoid a wall of due cards.
    static func run(
        context: ModelContext,
        stats: (Card) -> CardStats?,
        today: Date = .now,
        calendar: Calendar = .current
    ) {
        let cards: [Card]
        do {
            cards = try context.fetch(FetchDescriptor<Card>())
        } catch {
            return
        }

        var assigned: [(card: Card, box: Int)] = []
        for card in cards {
            guard let s = stats(card), s.seen >= DifficultyStore.minSeenForRanking else {
                card.boxIndex = 0
                card.nextDue = .distantPast
                continue
            }
            let wrongRate = Double(s.wrong) / Double(s.seen)
            let box: Int
            if wrongRate < 0.2 {
                box = 3
            } else if wrongRate < 0.4 {
                box = 2
            } else {
                box = 1
            }
            assigned.append((card, box))
        }

        let shuffled = assigned.shuffled()
        let dayStart = calendar.startOfDay(for: today)
        for (i, entry) in shuffled.enumerated() {
            entry.card.boxIndex = entry.box
            let offsetDays = i % staggerWindowDays
            entry.card.nextDue = calendar.date(byAdding: .day, value: offsetDays, to: dayStart) ?? dayStart
        }

        try? context.save()
    }
}

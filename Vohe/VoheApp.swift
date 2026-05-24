import SwiftUI
import SwiftData

@main
struct VoheApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Deck.self, Card.self, SessionResult.self, PausedSession.self
            )
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
        runSchedulerBackfillIfNeeded(container: modelContainer)
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(modelContainer)
    }
}

private func runSchedulerBackfillIfNeeded(container: ModelContainer) {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: SchedulerMigration.userDefaultsKey) else { return }
    let context = ModelContext(container)
    SchedulerMigration.run(
        context: context,
        stats: { card in
            guard let deckName = card.deck?.name else { return nil }
            return DifficultyStore.shared.stats(deckName: deckName, front: card.front, back: card.back)
        }
    )
    defaults.set(true, forKey: SchedulerMigration.userDefaultsKey)
}

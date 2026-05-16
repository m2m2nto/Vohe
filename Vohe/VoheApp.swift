import SwiftUI
import SwiftData

@main
struct VoheApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: [Deck.self, Card.self, SessionResult.self])
    }
}

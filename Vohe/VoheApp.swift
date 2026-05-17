import SwiftUI
import SwiftData

@main
struct VoheApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(for: [Deck.self, Card.self, SessionResult.self, PausedSession.self])
    }
}

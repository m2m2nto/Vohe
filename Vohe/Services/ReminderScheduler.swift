import Foundation
import UserNotifications

enum ReminderScheduler {
    static let userDefaultsKey = "remindersEnabled"

    private static let identifierPrefix = "vohe.reminder."
    private static let morningWindow: Range<Int> = 10..<13
    private static let eveningWindow: Range<Int> = 17..<21
    private static let daysAhead = 14

    private static let prompts: [(String, String)] = [
        ("Quick Vohe break?", "A two-minute round keeps the words sticky."),
        ("Time for a few cards", "Tap to run a short session."),
        ("Vocabulary check-in", "A handful of cards now beats cramming later."),
        ("Stretch your memory", "Even five cards is enough to make today count.")
    ]

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Replaces all pending Vohe reminders with two randomly-timed local notifications
    /// per day for the next `daysAhead` days. Skips today's pair if the user already
    /// practiced today.
    static func reschedule(lastPracticedAt: Date?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let practicedToday = lastPracticedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        let slots: [(String, Range<Int>)] = [("morning", morningWindow), ("evening", eveningWindow)]

        for dayOffset in 0..<daysAhead {
            if dayOffset == 0 && practicedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            for (slot, window) in slots {
                let hour = Int.random(in: window)
                let minute = Int.random(in: 0..<60)
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = hour
                comps.minute = minute
                guard let fireDate = calendar.date(from: comps), fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                let prompt = prompts.randomElement() ?? ("Vohe", "Time for a quick session.")
                content.title = prompt.0
                content.body = prompt.1
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                    repeats: false
                )
                let id = "\(identifierPrefix)\(dayOffset).\(slot)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }
}

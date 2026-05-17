import Foundation
import UserNotifications

struct ReminderSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case random, exact
        var id: String { rawValue }
    }

    var enabled: Bool
    var mode: Mode
    var count: Int
    var windowStartMinutes: Int
    var windowEndMinutes: Int
    var exactTimesMinutes: [Int]

    static let countRange: ClosedRange<Int> = 1...4
    static let defaultsKey = "reminderSettings.v2"

    static let `default` = ReminderSettings(
        enabled: false,
        mode: .random,
        count: 2,
        windowStartMinutes: 9 * 60,
        windowEndMinutes: 21 * 60,
        exactTimesMinutes: [9 * 60, 18 * 60]
    )

    static func load() -> ReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(self, from: data) else { return .default }
        return decoded
    }

    static func save(_ s: ReminderSettings) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

enum ReminderScheduler {
    private static let identifierPrefix = "vohe.reminder."
    private static let maxDaysAhead = 14
    private static let iosPendingCap = 64

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

    /// Replaces all pending Vohe reminders with daily notifications according to `settings`.
    /// Skips today's notifications if the user already practiced today.
    static func reschedule(settings: ReminderSettings, lastPracticedAt: Date?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)

        guard settings.enabled else { return }

        let settingsAuth = await center.notificationSettings()
        guard settingsAuth.authorizationStatus == .authorized || settingsAuth.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let practicedToday = lastPracticedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        let perDay = max(1, dailyMinuteOffsets(for: settings).count)
        let daysAhead = max(1, min(maxDaysAhead, iosPendingCap / perDay))

        for dayOffset in 0..<daysAhead {
            if dayOffset == 0 && practicedToday { continue }
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            for (slotIndex, minutes) in dailyMinuteOffsets(for: settings).enumerated() {
                var comps = calendar.dateComponents([.year, .month, .day], from: day)
                comps.hour = minutes / 60
                comps.minute = minutes % 60
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
                let id = "\(identifierPrefix)\(dayOffset).\(slotIndex)"
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }

    /// Returns the minute-of-day list for a single day under the given settings.
    /// Random mode partitions the window into `count` equal slots and picks a random minute in each.
    private static func dailyMinuteOffsets(for settings: ReminderSettings) -> [Int] {
        switch settings.mode {
        case .exact:
            let times = settings.exactTimesMinutes.filter { (0..<1440).contains($0) }
            return Array(Set(times)).sorted()
        case .random:
            let start = max(0, min(settings.windowStartMinutes, settings.windowEndMinutes))
            let end = min(1440, max(settings.windowStartMinutes, settings.windowEndMinutes))
            let count = min(max(1, settings.count), ReminderSettings.countRange.upperBound)
            guard end - start >= count else { return [start] }
            let slotWidth = (end - start) / count
            return (0..<count).map { i in
                let slotStart = start + i * slotWidth
                let slotEnd = (i == count - 1) ? end : slotStart + slotWidth
                return Int.random(in: slotStart..<max(slotStart + 1, slotEnd))
            }
        }
    }
}

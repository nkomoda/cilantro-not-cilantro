import Foundation
import UserNotifications

/// Reminds you to reinstall from Xcode before the app stops opening.
///
/// Apps installed with a free Apple ID expire 7 days after their provisioning profile was
/// created (1 year with the paid Developer Program). The profile is embedded in the app,
/// so we read the real expiry date from it and schedule a local notification. No server
/// or push entitlement needed. Every Run from Xcode installs a new profile and reschedules.
enum ExpiryReminder {
    private static let notificationID = "app-expiry-reminder"

    /// When this install stops working, or nil where there's no profile (Simulator, App Store).
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              // The profile is a signed blob with a plain XML plist inside.
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    /// True when the app expires within 2 days, to show a heads-up on the main screen.
    static var expiresSoon: Bool {
        guard let expirationDate else { return false }
        return expirationDate.timeIntervalSinceNow < 2 * 24 * 60 * 60
    }

    static func schedule() async {
        guard let expiry = expirationDate, let fireDate = reminderDate(for: expiry) else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let content = UNMutableNotificationContent()
        content.title = "Cilantro? expires soon"
        content.body = "It stops opening \(expiry.formatted(.dateTime.weekday(.wide).hour().minute())). "
            + "Connect to your Mac and press Run in Xcode to renew it for another 7 days."
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    /// The last 6 PM at least 2 hours before expiry, so it arrives in the evening with time to
    /// renew rather than in the middle of the night. Falls back to 2 hours before expiry.
    private static func reminderDate(for expiry: Date) -> Date? {
        let calendar = Calendar.current
        let latest = expiry.addingTimeInterval(-2 * 60 * 60)
        guard var evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: expiry) else { return nil }
        if evening > latest, let dayBefore = calendar.date(byAdding: .day, value: -1, to: evening) {
            evening = dayBefore
        }
        return [evening, latest].first { $0 > .now }
    }
}

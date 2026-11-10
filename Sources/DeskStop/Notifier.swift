import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for the toast-style
/// notifications that confirm a save or restore. Errors and destructive
/// confirmations still use `NSAlert`: those need the user's attention.
final class Notifier: NSObject {
    static let shared = Notifier()
    private let center = UNUserNotificationCenter.current()

    /// Invoked when the user taps Undo on a restore notification.
    var onUndo: (() -> Void)?

    private static let restoreCategory = "restore"
    private static let undoAction = "undo"

    private override init() {
        super.init()
        center.delegate = self
        let undo = UNNotificationAction(identifier: Self.undoAction, title: "Undo",
                                        options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.restoreCategory,
                                              actions: [undo], intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    /// Whether macOS will actually put a banner on screen for us.
    ///
    /// `authorizationStatus` alone is not enough: an app can be authorized with
    /// its alert style set to None, so notifications are delivered but silently
    /// filed in Notification Centre.
    enum DeliveryStatus {
        /// A banner will appear.
        case willShow
        /// Never authorized, or denied.
        case notAuthorized
        /// Authorized, but macOS alert style is None — delivered, never shown.
        case bannersDisabled
    }

    /// Asks the OS for permission to post notifications. Safe to call on
    /// every launch — the system only prompts once, and a denied app is not
    /// re-prompted.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("DeskStop notification auth error: \(error)")
            } else {
                NSLog("DeskStop notification auth granted: \(granted)")
            }
        }
    }

    func deliveryStatus(completion: @escaping (DeliveryStatus) -> Void) {
        center.getNotificationSettings { settings in
            let result: DeliveryStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                result = settings.alertStyle == .none ? .bannersDisabled : .willShow
            default:
                result = .notAuthorized
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Post a notification. When `undoable`, it carries an Undo action button
    /// that calls `onUndo`.
    func notify(title: String, body: String, undoable: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if undoable { content.categoryIdentifier = Self.restoreCategory }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error = error {
                NSLog("DeskStop notification deliver error: \(error)")
            }
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Show banners even when our app is frontmost. Without this, notifications
    /// fired while the user is interacting with our (modal) recorder panel
    /// would be silently swallowed.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Handle the Undo action tap.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == Self.undoAction {
            DispatchQueue.main.async { [weak self] in self?.onUndo?() }
        }
        completionHandler()
    }
}

extension UserDefaults {
    private static let notificationsKey = "showSuccessNotifications"

    var showSuccessNotifications: Bool {
        get { object(forKey: Self.notificationsKey) as? Bool ?? true }
        set { set(newValue, forKey: Self.notificationsKey) }
    }
}

import UIKit
import UserNotifications

final class CloudNotifications: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let tokenChanged = Notification.Name("DonyCloudPushTokenChanged")
    static let opened = Notification.Name("DonyCloudNotificationOpened")
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "cloudPushToken")
        NotificationCenter.default.post(name: Self.tokenChanged, object: nil)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        NotificationCenter.default.post(name: Self.opened, object: nil, userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }
}

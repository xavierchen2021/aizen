//
//  TerminalNotificationManager.swift
//  aizen
//
//  Lightweight helper to send user notifications for terminal events.
//

import Foundation
import UserNotifications
import os.log

final class TerminalNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TerminalNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger.terminal
    private var permissionRequested = false

    private override init() {
        super.init()
        center.delegate = self
    }

    func notify(title: String, body: String) {
        requestPermissionIfNeeded { [weak self] granted in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )

            self?.center.add(request) { error in
                if let error {
                    self?.logger.error("Failed to deliver terminal notification: \(error.localizedDescription)")
                }
            }
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    private func requestPermissionIfNeeded(completion: @escaping (Bool) -> Void) {
        // Only ask once per launch to avoid nagging
        if permissionRequested {
            center.getNotificationSettings { settings in
                completion(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
            return
        }
        permissionRequested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            completion(granted)
        }
    }
}

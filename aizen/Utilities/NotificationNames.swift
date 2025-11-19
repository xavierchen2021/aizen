//
//  NotificationNames.swift
//  aizen
//
//  Centralized notification names for app-wide events
//

import Foundation

extension Notification.Name {
    // MARK: - Chat View Lifecycle

    /// Posted when chat view appears and becomes active
    static let chatViewDidAppear = Notification.Name("ChatViewDidAppear")

    /// Posted when chat view disappears and becomes inactive
    static let chatViewDidDisappear = Notification.Name("ChatViewDidDisappear")

    // MARK: - Keyboard Shortcuts

    /// Posted when Shift+Tab is pressed to cycle through available modes
    static let cycleModeShortcut = Notification.Name("CycleModeShortcut")

    /// Posted when Escape is pressed to interrupt the current agent operation
    static let interruptAgentShortcut = Notification.Name("InterruptAgentShortcut")

    /// Posted when Command+P is pressed to open file search
    static let fileSearchShortcut = Notification.Name("FileSearchShortcut")
}

//
//  TerminalSessionManager.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import Foundation

class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private var terminals: [String: GhosttyTerminalView] = [:]
    private var scrollViews: [String: TerminalScrollView] = [:]

    private init() {}

    func getTerminal(for sessionId: UUID, paneId: String) -> GhosttyTerminalView? {
        let key = "\(sessionId.uuidString)-\(paneId)"
        return terminals[key]
    }

    func setTerminal(_ terminal: GhosttyTerminalView, for sessionId: UUID, paneId: String) {
        let key = "\(sessionId.uuidString)-\(paneId)"
        terminals[key] = terminal
    }

    func removeTerminal(for sessionId: UUID, paneId: String) {
        let key = "\(sessionId.uuidString)-\(paneId)"
        terminals.removeValue(forKey: key)
        scrollViews.removeValue(forKey: key)
    }

    func removeAllTerminals(for sessionId: UUID) {
        let prefix = sessionId.uuidString
        terminals = terminals.filter { !$0.key.hasPrefix(prefix) }
        scrollViews = scrollViews.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: - Scroll View Management

    func getScrollView(for sessionId: UUID, paneId: String) -> TerminalScrollView? {
        let key = "\(sessionId.uuidString)-\(paneId)"
        return scrollViews[key]
    }

    func setScrollView(_ scrollView: TerminalScrollView, for sessionId: UUID, paneId: String) {
        let key = "\(sessionId.uuidString)-\(paneId)"
        scrollViews[key] = scrollView
    }

    func getTerminalCount(for sessionId: UUID) -> Int {
        let prefix = sessionId.uuidString
        return terminals.keys.filter { $0.hasPrefix(prefix) }.count
    }

    /// Check if any terminal pane needs confirmation before closing
    @MainActor
    func hasRunningProcess(for sessionId: UUID, paneIds: [String]) -> Bool {
        for paneId in paneIds {
            if let terminal = getTerminal(for: sessionId, paneId: paneId),
               terminal.needsConfirmQuit {
                return true
            }
        }
        return false
    }

    /// Check if a specific pane needs confirmation before closing
    @MainActor
    func paneHasRunningProcess(for sessionId: UUID, paneId: String) -> Bool {
        if let terminal = getTerminal(for: sessionId, paneId: paneId) {
            return terminal.needsConfirmQuit
        }
        return false
    }
}

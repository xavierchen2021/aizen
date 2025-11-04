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
    }

    func removeAllTerminals(for sessionId: UUID) {
        let prefix = sessionId.uuidString
        terminals = terminals.filter { !$0.key.hasPrefix(prefix) }
    }
}

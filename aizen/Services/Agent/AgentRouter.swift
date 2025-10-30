import Foundation
import SwiftUI
import Combine

class AgentRouter: ObservableObject {
    @Published var activeSessions: [String: AgentSession] = [:]

    private let defaultAgentKey = "defaultACPAgent"

    var defaultAgent: String {
        get {
            UserDefaults.standard.string(forKey: defaultAgentKey) ?? "claude"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultAgentKey)
        }
    }

    private let agentAliases: [String: String] = [
        "claude": "claude",
        "codex": "codex",
        "gemini": "gemini"
    ]

    @MainActor
    init() {
        // Initialize default sessions
        activeSessions["claude"] = AgentSession(agentName: "claude")
        activeSessions["codex"] = AgentSession(agentName: "codex")
        activeSessions["gemini"] = AgentSession(agentName: "gemini")
    }

    @MainActor
    func parseAndRoute(message: String) -> (agentName: String, cleanedMessage: String) {
        let pattern = "^@(\\w+)\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (defaultAgent, message)
        }

        let nsRange = NSRange(message.startIndex..., in: message)

        if let match = regex.firstMatch(in: message, options: [], range: nsRange) {
            if let mentionRange = Range(match.range(at: 1), in: message) {
                let mentionedAgent = String(message[mentionRange]).lowercased()

                if let resolvedAgent = agentAliases[mentionedAgent] {
                    let cleanedMessage = regex.stringByReplacingMatches(
                        in: message,
                        options: [],
                        range: nsRange,
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespaces)

                    ensureSession(for: resolvedAgent)
                    return (resolvedAgent, cleanedMessage)
                }
            }
        }

        return (defaultAgent, message)
    }

    func getSession(for agentName: String) -> AgentSession? {
        return activeSessions[agentName]
    }

    @MainActor
    func ensureSession(for agentName: String) {
        if activeSessions[agentName] == nil {
            activeSessions[agentName] = AgentSession(agentName: agentName)
        }
    }

    func removeSession(for agentName: String) {
        activeSessions.removeValue(forKey: agentName)
    }

    func clearAllSessions() {
        activeSessions.removeAll()
    }
}

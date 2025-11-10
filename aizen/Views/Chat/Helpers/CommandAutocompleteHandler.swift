//
//  CommandAutocompleteHandler.swift
//  aizen
//
//  Handles command autocomplete filtering logic
//

import Foundation

@MainActor
class CommandAutocompleteHandler {
    func updateCommandSuggestions(_ text: String, currentAgentSession: AgentSession?) -> [AvailableCommand] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        guard trimmed.hasPrefix("/") else {
            return []
        }

        let commandPart = String(trimmed.dropFirst()).lowercased()

        guard let agentSession = currentAgentSession else {
            return []
        }

        if commandPart.isEmpty {
            return agentSession.availableCommands
        } else {
            return agentSession.availableCommands.filter { command in
                command.name.lowercased().hasPrefix(commandPart) ||
                command.description.lowercased().contains(commandPart)
            }
        }
    }
}

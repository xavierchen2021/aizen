//
//  ChatControlsBar.swift
//  aizen
//
//  Agent selector and mode controls bar
//

import SwiftUI

struct ChatControlsBar: View {
    let selectedAgent: String
    let currentAgentSession: AgentSession?
    let hasModes: Bool
    let onAgentSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            AgentSelectorMenu(selectedAgent: selectedAgent, onAgentSelect: onAgentSelect)

            if hasModes, let agentSession = currentAgentSession {
                ModeSelectorView(session: agentSession)
            }

            Spacer()
        }
    }
}

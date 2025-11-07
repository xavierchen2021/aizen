//
//  AgentSelectorMenu.swift
//  aizen
//
//  Agent selection menu component
//

import SwiftUI

struct AgentSelectorMenu: View {
    let selectedAgent: String
    let onAgentSelect: (String) -> Void

    @State private var enabledAgents: [AgentMetadata] = []

    // Use computed property directly instead of state
    private var selectedAgentMetadata: AgentMetadata? {
        AgentRegistry.shared.getMetadata(for: selectedAgent)
    }

    var body: some View {
        Menu {
            ForEach(enabledAgents, id: \.id) { agentMetadata in
                Button {
                    onAgentSelect(agentMetadata.id)
                } label: {
                    HStack {
                        AgentIconView(metadata: agentMetadata, size: 14)
                        Text(agentMetadata.name)
                        Spacer()
                        if agentMetadata.id == selectedAgent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                AgentIconView(agent: selectedAgent, size: 12)
                Text(selectedAgentMetadata?.name ?? selectedAgent.capitalized)
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .onAppear {
            enabledAgents = AgentRegistry.shared.getEnabledAgents()
        }
        .id(selectedAgent) // Force view recreation when selectedAgent changes
    }
}

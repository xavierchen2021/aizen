//
//  WorktreeSessionTabs.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 04.11.25.
//

import SwiftUI

// MARK: - Session Tab Button

struct SessionTabButton<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    let content: Content

    @State private var isHovering = false

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = content()
    }


    var body: some View {
        Button(action: action) {
            content
                .padding(6)
                .background(
                    isSelected ?
                    Color(nsColor: .separatorColor) :
                    (isHovering ? Color(nsColor: .separatorColor).opacity(0.5) : Color.clear),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Session Tabs ScrollView

struct SessionTabsScrollView: View {
    let selectedTab: String
    let chatSessions: [ChatSession]
    let terminalSessions: [TerminalSession]
    @Binding var selectedChatSessionId: UUID?
    @Binding var selectedTerminalSessionId: UUID?
    let onCloseChatSession: (ChatSession) -> Void
    let onCloseTerminalSession: (TerminalSession) -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    if selectedTab == "chat" && !chatSessions.isEmpty {
                        ForEach(chatSessions) { session in
                            SessionTabButton(
                                isSelected: selectedChatSessionId == session.id,
                                action: { selectedChatSessionId = session.id }
                            ) {
                                HStack(spacing: 6) {
                                    AgentIconView(agent: session.agentName ?? "claude", size: 14)

                                    Text(session.title ?? session.agentName?.capitalized ?? String(localized: "worktree.session.chat"))
                                        .font(.callout)

                                    Button {
                                        onCloseChatSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    } else if selectedTab == "terminal" && !terminalSessions.isEmpty {
                        ForEach(terminalSessions) { session in
                            SessionTabButton(
                                isSelected: selectedTerminalSessionId == session.id,
                                action: { selectedTerminalSessionId = session.id }
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "terminal")
                                        .font(.system(size: 12))
                                    Text(session.title ?? String(localized: "worktree.session.terminal"))
                                        .font(.callout)

                                    Button {
                                        onCloseTerminalSession(session)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: 600)
    }
}

//
//  TerminalTabView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import os.log

struct TerminalTabView: View {
    @ObservedObject var worktree: Worktree
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: RepositoryManager

    private let sessionManager = TerminalSessionManager.shared
    private let logger = Logger.terminal

    var sessions: [TerminalSession] {
        let sessions = (worktree.terminalSessions as? Set<TerminalSession>) ?? []
        return sessions.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
    }

    var body: some View {
        if sessions.isEmpty {
            terminalEmptyState
        } else {
            ZStack {
                ForEach(sessions) { session in
                    if selectedSessionId == session.id {
                        SplitTerminalView(
                            worktree: worktree,
                            session: session,
                            sessionManager: sessionManager,
                            isSelected: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.identity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if selectedSessionId == nil {
                    selectedSessionId = sessions.first?.id
                }
            }
        }
    }

    private var terminalEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text("terminal.noSessions", bundle: .main)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("terminal.openInWorktree", bundle: .main)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("terminal.new", bundle: .main)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func createNewSession() {
        guard let context = worktree.managedObjectContext else { return }

        let session = TerminalSession(context: context)
        session.id = UUID()
        session.title = String(localized: "worktree.session.terminalTitle", defaultValue: "Terminal \(sessions.count + 1)", bundle: .main)
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedSessionId = session.id
        } catch {
            logger.error("Failed to create terminal session: \(error.localizedDescription)")
        }
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        selectedSessionId: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}

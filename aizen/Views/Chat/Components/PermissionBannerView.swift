//
//  PermissionBannerView.swift
//  aizen
//
//  Glass toast notification for pending permission requests in other sessions.
//

import SwiftUI
import CoreData

struct PermissionBannerView: View {
    let currentChatSessionId: UUID?
    let onNavigate: (UUID) -> Void

    @ObservedObject private var chatSessionManager = ChatSessionManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme

    private var pendingSessionInfo: (sessionId: UUID, worktreeName: String, message: String?)? {
        for sessionId in chatSessionManager.sessionsWithPendingPermissions {
            if sessionId != currentChatSessionId {
                let (worktreeName, message) = fetchSessionInfo(for: sessionId)
                return (sessionId, worktreeName, message)
            }
        }
        return nil
    }

    private func fetchSessionInfo(for chatSessionId: UUID) -> (worktreeName: String, message: String?) {
        let request: NSFetchRequest<ChatSession> = ChatSession.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", chatSessionId as CVarArg)
        request.fetchLimit = 1

        do {
            if let session = try viewContext.fetch(request).first,
               let worktree = session.worktree {
                let name = worktree.branch ?? "Chat"
                // Get permission message from agent session
                let agentSession = ChatSessionManager.shared.getAgentSession(for: chatSessionId)
                let message = agentSession?.permissionHandler.permissionRequest?.message
                return (name, message)
            }
        } catch {}
        return ("Chat", nil)
    }

    var body: some View {
        if let info = pendingSessionInfo {
            bannerContent(info: info)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: info.sessionId)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func bannerContent(info: (sessionId: UUID, worktreeName: String, message: String?)) -> some View {
        Button {
            onNavigate(info.sessionId)
        } label: {
            HStack(spacing: 10) {
                // Pulsing indicator
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(.orange.opacity(0.5), lineWidth: 2)
                            .scaleEffect(1.5)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("permission.banner.title \(info.worktreeName)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let message = info.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 380)
            .background { glassBackground }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 20, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if #available(macOS 26.0, *) {
            ZStack {
                GlassEffectContainer {
                    shape
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular.tint(tintColor), in: shape)
                }
                .allowsHitTesting(false)

                shape
                    .fill(scrimColor)
                    .allowsHitTesting(false)
            }
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

    private var tintColor: Color {
        colorScheme == .dark ? .black.opacity(0.22) : .white.opacity(0.6)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? .white.opacity(0.14) : .black.opacity(0.08)
    }

    private var scrimColor: Color {
        colorScheme == .dark ? .black.opacity(0.12) : .white.opacity(0.06)
    }
}

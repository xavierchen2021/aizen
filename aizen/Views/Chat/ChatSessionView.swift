//
//  ChatSessionView.swift
//  aizen
//
//  Chat session interface with messages and input
//

import SwiftUI
import CoreData

struct ChatSessionView: View {
    let worktree: Worktree
    @ObservedObject var session: ChatSession
    let sessionManager: ChatSessionManager

    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var viewModel: ChatSessionViewModel

    // UI-only state
    @State private var showingAttachmentPicker = false
    @State private var showingAuthSheet = false
    @State private var showingAgentPlan = false
    @State private var showingCommandAutocomplete = false
    @State private var showingVoiceRecording = false
    @State private var showingPermissionError = false
    @State private var permissionErrorMessage = ""
    @State private var showingAgentSetupDialog = false

    init(worktree: Worktree, session: ChatSession, sessionManager: ChatSessionManager, viewContext: NSManagedObjectContext) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager
        self._viewContext = Environment(\.managedObjectContext)

        let vm = ChatSessionViewModel(
            worktree: worktree,
            session: session,
            sessionManager: sessionManager,
            viewContext: viewContext
        )
        self._viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ChatMessageList(
                        timelineItems: viewModel.timelineItems,
                        isProcessing: viewModel.isProcessing,
                        selectedAgent: viewModel.selectedAgent,
                        currentThought: viewModel.currentAgentSession?.currentThought,
                        onScrollProxyReady: { proxy in
                            viewModel.scrollProxy = proxy
                        },
                        onAppear: viewModel.loadMessages,
                        renderInlineMarkdown: viewModel.renderInlineMarkdown
                    )

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        if let agentSession = viewModel.currentAgentSession,
                           viewModel.showingPermissionAlert,
                           let request = viewModel.currentPermissionRequest {
                            HStack {
                                PermissionRequestView(session: agentSession, request: request)
                                    .transition(.opacity)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                        }

                        if !viewModel.attachments.isEmpty {
                            attachmentChipsView
                                .padding(.horizontal, 20)
                        }

                        ChatControlsBar(
                            selectedAgent: viewModel.selectedAgent,
                            currentAgentSession: viewModel.currentAgentSession,
                            onAgentSelect: viewModel.requestAgentSwitch
                        )
                        .padding(.horizontal, 20)

                        ChatInputBar(
                            inputText: $viewModel.inputText,
                            attachments: $viewModel.attachments,
                            isProcessing: $viewModel.isProcessing,
                            showingVoiceRecording: $showingVoiceRecording,
                            showingAttachmentPicker: $showingAttachmentPicker,
                            showingCommandAutocomplete: $showingCommandAutocomplete,
                            showingPermissionError: $showingPermissionError,
                            permissionErrorMessage: $permissionErrorMessage,
                            commandSuggestions: viewModel.commandSuggestions,
                            session: viewModel.currentAgentSession,
                            selectedAgent: viewModel.selectedAgent,
                            isSessionReady: viewModel.isSessionReady,
                            audioService: viewModel.audioService,
                            onSend: viewModel.sendMessage,
                            onCancel: viewModel.cancelCurrentPrompt,
                            onCommandSelect: viewModel.selectCommand
                        )
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }

                if showingAgentPlan, let plan = viewModel.currentAgentSession?.agentPlan {
                    AgentPlanSidebarView(plan: plan, isShowing: $showingAgentPlan)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .focusedSceneValue(\.chatActions, ChatActions(cycleModeForward: viewModel.cycleModeForward))
        .onAppear {
            viewModel.setupAgentSession()
        }
        .onChange(of: viewModel.selectedAgent) { _ in
            viewModel.setupAgentSession()
        }
        .onChange(of: viewModel.inputText) { newText in
            viewModel.updateCommandSuggestions(newText)
            updateCommandAutocompleteVisibility()
        }
        .onReceive(viewModel.$currentAgentSession) { session in
            if let session = session {
                if session.needsAuthentication {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAuthSheet = true
                    }
                }
                if session.needsAgentSetup {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showingAgentSetupDialog = true
                    }
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingAgentPlan = session.agentPlan != nil
                }
            }
        }
        .sheet(isPresented: $showingAuthSheet) {
            if let agentSession = viewModel.currentAgentSession {
                AuthenticationSheet(session: agentSession)
            }
        }
        .sheet(isPresented: $showingAgentSetupDialog) {
            if let agentSession = viewModel.currentAgentSession {
                AgentSetupDialog(session: agentSession)
            }
        }
        .alert(String(localized: "chat.agent.switch.title"), isPresented: $viewModel.showingAgentSwitchWarning) {
            Button(String(localized: "chat.button.cancel"), role: .cancel) {
                viewModel.pendingAgentSwitch = nil
            }
            Button(String(localized: "chat.button.switch"), role: .destructive) {
                if let newAgent = viewModel.pendingAgentSwitch {
                    viewModel.performAgentSwitch(to: newAgent)
                }
            }
        } message: {
            Text("chat.agent.switch.message", bundle: .main)
        }
        .alert(String(localized: "chat.permission.title"), isPresented: $showingPermissionError) {
            Button(String(localized: "chat.permission.openSettings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button(String(localized: "chat.button.cancel"), role: .cancel) {}
        } message: {
            Text(permissionErrorMessage)
        }
    }

    // MARK: - Subviews

    private var attachmentChipsView: some View {
        HStack(spacing: 8) {
            ForEach(viewModel.attachments, id: \.self) { attachment in
                AttachmentChipWithDelete(url: attachment) {
                    viewModel.removeAttachment(attachment)
                }
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func updateCommandAutocompleteVisibility() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            showingCommandAutocomplete = !viewModel.commandSuggestions.isEmpty
        }
    }
}

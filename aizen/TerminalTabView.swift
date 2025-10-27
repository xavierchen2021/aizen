//
//  TerminalTabView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import SwiftTerm
import AppKit

class TerminalSessionManager {
    static let shared = TerminalSessionManager()

    private var terminals: [String: LocalProcessTerminalView] = [:]

    private init() {}

    func getTerminal(for sessionId: UUID, paneId: String) -> LocalProcessTerminalView? {
        let key = "\(sessionId.uuidString)-\(paneId)"
        return terminals[key]
    }

    func setTerminal(_ terminal: LocalProcessTerminalView, for sessionId: UUID, paneId: String) {
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

struct TerminalTabView: View {
    @ObservedObject var worktree: Worktree
    @Binding var selectedSessionId: UUID?
    @ObservedObject var repositoryManager: RepositoryManager

    private let sessionManager = TerminalSessionManager.shared

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
                    SplitTerminalView(
                        worktree: worktree,
                        session: session,
                        sessionManager: sessionManager
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(selectedSessionId == session.id ? 1 : 0)
                }
            }
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
                    Text("No Terminal Sessions")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Open a terminal in this worktree")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                createNewSession()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Terminal")
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
        session.title = "Terminal \(sessions.count + 1)"
        session.createdAt = Date()
        session.worktree = worktree

        do {
            try context.save()
            selectedSessionId = session.id
        } catch {
            print("Failed to create terminal session: \(error)")
        }
    }
}

// MARK: - Split Terminal View

struct SplitTerminalView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let sessionManager: TerminalSessionManager

    @State private var layout: SplitNode
    @State private var focusedPaneId: String

    init(worktree: Worktree, session: TerminalSession, sessionManager: TerminalSessionManager) {
        self.worktree = worktree
        self.session = session
        self.sessionManager = sessionManager

        // Load layout from session or create default
        if let layoutJSON = session.splitLayout,
           let decoded = SplitLayoutHelper.decode(layoutJSON) {
            _layout = State(initialValue: decoded)
            _focusedPaneId = State(initialValue: session.focusedPaneId ?? decoded.allPaneIds().first ?? "")
        } else {
            let defaultLayout = SplitLayoutHelper.createDefault()
            _layout = State(initialValue: defaultLayout)
            _focusedPaneId = State(initialValue: defaultLayout.allPaneIds().first ?? "")
        }
    }

    var body: some View {
        renderNode(layout)
            .padding(.top, 1)
            .onAppear {
                saveLayout()
            }
            .onChange(of: layout) { _, _ in
                saveLayout()
            }
            .onChange(of: focusedPaneId) { _, newValue in
                session.focusedPaneId = newValue
                saveContext()
            }
            .focusedSceneValue(\.terminalSplitActions, TerminalSplitActions(
                splitHorizontal: splitHorizontal,
                splitVertical: splitVertical,
                closePane: closePane
            ))
    }

    private func renderNode(_ node: SplitNode) -> AnyView {
        switch node {
        case .leaf(let paneId):
            return AnyView(
                TerminalPaneView(
                    worktree: worktree,
                    session: session,
                    paneId: paneId,
                    isFocused: focusedPaneId == paneId,
                    sessionManager: sessionManager,
                    onFocus: { focusedPaneId = paneId },
                    onProcessExit: { handleProcessExit(for: paneId) }
                )
            )

        case .hsplit(let ratio, let left, let right):
            return AnyView(
                HSplitView {
                    renderNode(left)
                        .layoutPriority(ratio)
                    renderNode(right)
                        .layoutPriority(1 - ratio)
                }
            )

        case .vsplit(let ratio, let top, let bottom):
            return AnyView(
                VSplitView {
                    renderNode(top)
                        .layoutPriority(ratio)
                    renderNode(bottom)
                        .layoutPriority(1 - ratio)
                }
            )
        }
    }

    private func splitHorizontal() {
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.hsplit(
            ratio: 0.5,
            left: .leaf(paneId: focusedPaneId),
            right: .leaf(paneId: newPaneId)
        )
        layout = layout.replacingPane(focusedPaneId, with: newSplit)
        focusedPaneId = newPaneId
    }

    private func splitVertical() {
        let newPaneId = UUID().uuidString
        let newSplit = SplitNode.vsplit(
            ratio: 0.5,
            top: .leaf(paneId: focusedPaneId),
            bottom: .leaf(paneId: newPaneId)
        )
        layout = layout.replacingPane(focusedPaneId, with: newSplit)
        focusedPaneId = newPaneId
    }

    private func handleProcessExit(for paneId: String) {
        // Remove terminal from manager
        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: paneId)
        }

        let paneCount = layout.allPaneIds().count

        if paneCount == 1 {
            // Only one pane - delete the entire terminal session
            // Use a small delay to allow SwiftUI to process the deletion gracefully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak session] in
                guard let session = session,
                      let context = session.managedObjectContext else { return }
                context.delete(session)
                do {
                    try context.save()
                } catch {
                    print("Failed to delete terminal session: \(error)")
                }
            }
        } else {
            // Multiple panes - just close this one
            if let newLayout = layout.removingPane(paneId) {
                layout = newLayout
                // If we closed the focused pane, focus another one
                if focusedPaneId == paneId {
                    if let firstPane = layout.allPaneIds().first {
                        focusedPaneId = firstPane
                    }
                }
            }
        }
    }

    private func closePane() {
        guard layout.allPaneIds().count > 1 else { return }

        // Remove terminal from manager
        if let sessionId = session.id {
            sessionManager.removeTerminal(for: sessionId, paneId: focusedPaneId)
        }

        if let newLayout = layout.removingPane(focusedPaneId) {
            layout = newLayout
            // Focus first available pane
            if let firstPane = layout.allPaneIds().first {
                focusedPaneId = firstPane
            }
        }
    }

    private func saveLayout() {
        if let json = SplitLayoutHelper.encode(layout) {
            session.splitLayout = json
            saveContext()
        }
    }

    private func saveContext() {
        guard let context = session.managedObjectContext else { return }
        do {
            try context.save()
        } catch {
            print("Failed to save split layout: \(error)")
        }
    }
}

// MARK: - Terminal Pane View

struct TerminalPaneView: View {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let isFocused: Bool
    let sessionManager: TerminalSessionManager
    let onFocus: () -> Void
    let onProcessExit: () -> Void

    var body: some View {
        TerminalViewWrapper(
            worktree: worktree,
            session: session,
            paneId: paneId,
            sessionManager: sessionManager,
            onProcessExit: onProcessExit
        )
        .opacity(isFocused ? 1.0 : 0.6)
        .onTapGesture {
            onFocus()
        }
    }
}

// MARK: - Terminal Split Actions (for keyboard shortcuts)

struct TerminalSplitActions {
    let splitHorizontal: () -> Void
    let splitVertical: () -> Void
    let closePane: () -> Void
}

private struct TerminalSplitActionsKey: FocusedValueKey {
    typealias Value = TerminalSplitActions
}

extension FocusedValues {
    var terminalSplitActions: TerminalSplitActions? {
        get { self[TerminalSplitActionsKey.self] }
        set { self[TerminalSplitActionsKey.self] = newValue }
    }
}


// MARK: - Terminal View Coordinator

class TerminalViewCoordinator: LocalProcessTerminalViewDelegate {
    let onProcessExit: () -> Void

    init(onProcessExit: @escaping () -> Void) {
        self.onProcessExit = onProcessExit
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // Not needed for our use case
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // Not needed for our use case
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // Not needed for our use case
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Call the closure on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onProcessExit()
        }
    }
}

// MARK: - Terminal View Wrapper

struct TerminalViewWrapper: NSViewRepresentable {
    @ObservedObject var worktree: Worktree
    @ObservedObject var session: TerminalSession
    let paneId: String
    let sessionManager: TerminalSessionManager
    let onProcessExit: () -> Void

    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    func makeCoordinator() -> TerminalViewCoordinator {
        TerminalViewCoordinator(onProcessExit: onProcessExit)
    }

    func makeNSView(context: Context) -> NSView {
        // Guard against deleted session
        guard let sessionId = session.id else {
            return NSView(frame: .zero)
        }

        // Check if terminal already exists for this pane
        if let existingTerminal = sessionManager.getTerminal(for: sessionId, paneId: paneId) {
            // Set process delegate even for existing terminals
            existingTerminal.processDelegate = context.coordinator
            return existingTerminal
        }

        // Create new terminal
        let terminalView = LocalProcessTerminalView(frame: .zero)

        // Set terminal colors from settings
        let bgColor = NSColor(hex: terminalBackgroundColor) ?? .black
        let fgColor = NSColor(hex: terminalForegroundColor) ?? .white
        let cursorColor = NSColor(hex: terminalCursorColor) ?? fgColor
        let selectionBg = NSColor(hex: terminalSelectionBackground) ?? fgColor.withAlphaComponent(0.2)

        // Set native colors first
        terminalView.nativeBackgroundColor = bgColor
        terminalView.nativeForegroundColor = fgColor

        // Then apply ANSI color palette (this should override the palette but keep bg/fg)
        if let palette = parseANSIPalette(terminalPalette) {
            terminalView.installColors(palette)
        }

        // Set cursor and selection colors
        terminalView.caretColor = cursorColor
        terminalView.selectedTextBackgroundColor = selectionBg

        // Apply font settings
        if let font = NSFont(name: terminalFontName, size: terminalFontSize) {
            terminalView.font = font
        }

        if let path = worktree.path {
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["COLORTERM"] = "truecolor"

            // Get user's default shell
            let shell = env["SHELL"] ?? "/bin/zsh"
            let shellName = (shell as NSString).lastPathComponent

            terminalView.startProcess(
                executable: shell,
                args: ["-l", "-c", "cd '\(path)' && exec $SHELL"],
                environment: env.map { $0.key + "=" + $0.value },
                execName: shellName
            )
        }

        // Set process delegate for termination handling
        terminalView.processDelegate = context.coordinator

        // Store terminal in manager for persistence
        sessionManager.setTerminal(terminalView, for: sessionId, paneId: paneId)

        return terminalView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Terminal view doesn't need updates
    }

    private func parseANSIPalette(_ paletteString: String) -> [SwiftTerm.Color]? {
        let hexColors = paletteString.split(separator: ",").map(String.init)
        guard hexColors.count == 16 else { return nil }

        var parsed: [SwiftTerm.Color] = []

        for hex in hexColors {
            guard let nsColor = NSColor(hex: hex),
                  let components = nsColor.usingColorSpace(.deviceRGB)?.cgColor.components else {
                return nil
            }

            // SwiftTerm.Color uses 16-bit values (0-65535), so multiply by 257 or use * 65535
            let r = UInt16(components[0] * 65535)
            let g = UInt16(components[1] * 65535)
            let b = UInt16(components[2] * 65535)

            parsed.append(SwiftTerm.Color(red: r, green: g, blue: b))
        }

        return parsed
    }
}

#Preview {
    TerminalTabView(
        worktree: Worktree(),
        selectedSessionId: .constant(nil),
        repositoryManager: RepositoryManager(viewContext: PersistenceController.preview.container.viewContext)
    )
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

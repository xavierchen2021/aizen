//
//  FileSearchWindowController.swift
//  aizen
//
//  Created on 2025-11-19.
//

import AppKit
import SwiftUI

class FileSearchWindowController: NSWindowController {
    private var eventMonitor: Any?
    private var appDeactivationObserver: NSObjectProtocol?

    convenience init(worktreePath: String, onFileSelected: @escaping (String) -> Void) {
        let window = FileSearchWindow(worktreePath: worktreePath, onFileSelected: onFileSelected)
        self.init(window: window)
        setupAppObservers()
    }

    deinit {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupAppObservers() {
        // Close window when app is deactivated
        appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.closeWindow()
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let window = window as? FileSearchWindow else { return }

        // Get the main window frame
        if let mainWindow = NSApp.mainWindow {
            let mainFrame = mainWindow.frame
            let windowSize = window.frame.size

            // Center horizontally, position much higher vertically
            let x = mainFrame.origin.x + (mainFrame.width - windowSize.width) / 2
            let y = mainFrame.origin.y + mainFrame.height - windowSize.height - 80

            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)

        // Force the window to become key and activate it
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()

        // Ensure the text field gets focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.makeFirstResponder(window.contentView)
        }
    }

    func closeWindow() {
        window?.close()
    }
}

class FileSearchWindow: NSWindow {
    init(worktreePath: String, onFileSelected: @escaping (String) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 70),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.styleMask.insert(.fullSizeContentView)

        let hostingView = NSHostingView(
            rootView: FileSearchWindowContent(
                worktreePath: worktreePath,
                onFileSelected: onFileSelected,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )

        self.contentView = hostingView
    }

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return false
    }
}

struct FileSearchWindowContent: View {
    let worktreePath: String
    let onFileSelected: (String) -> Void
    let onClose: () -> Void

    @StateObject private var viewModel: FileSearchViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var eventMonitor: Any?

    init(worktreePath: String, onFileSelected: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.worktreePath = worktreePath
        self.onFileSelected = onFileSelected
        self.onClose = onClose
        self._viewModel = StateObject(wrappedValue: FileSearchViewModel(worktreePath: worktreePath))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search input - circular/pill shaped
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .medium))

                TextField("Search files...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isSearchFocused)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 15)

            // Results - only show when typing
            if !viewModel.searchQuery.isEmpty {
                resultsCard
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(width: 700)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.clear)
        .compositingGroup()
        .onAppear {
            // Focus immediately
            isSearchFocused = true

            // Backup focus after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }

            // Another backup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isSearchFocused = true
            }

            viewModel.indexFiles()
            setupKeyboardMonitoring()
        }
        .onDisappear {
            removeKeyboardMonitoring()
        }
        .onChange(of: viewModel.searchQuery) { _ in
            viewModel.performSearch()
            updateWindowHeight()
        }
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            if viewModel.isIndexing {
                indexingView
            } else if viewModel.results.isEmpty {
                emptyResultsView
            } else {
                resultsListView
            }
        }
        .frame(width: 700)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
        )
        .shadow(color: .black.opacity(0.25), radius: 25, x: 0, y: 15)
        .compositingGroup()
    }

    private var indexingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No files found")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                        resultRow(result: result, index: index, isSelected: index == viewModel.selectedIndex)
                            .id(index)
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .frame(maxHeight: 450)
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func resultRow(result: FileSearchResult, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            FileIconView(path: result.path, size: 20)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.name)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .primary)

                Text(result.relativePath)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectFile(result)
        }
    }

    private func setupKeyboardMonitoring() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 125 { // Down arrow
                viewModel.moveSelectionDown()
                return nil
            } else if event.keyCode == 126 { // Up arrow
                viewModel.moveSelectionUp()
                return nil
            } else if event.keyCode == 36 { // Return
                if let result = viewModel.getSelectedResult() {
                    selectFile(result)
                }
                return nil
            } else if event.keyCode == 53 { // Escape
                onClose()
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func selectFile(_ result: FileSearchResult) {
        viewModel.trackFileOpen(result.path)
        onFileSelected(result.path)
        onClose()
    }

    private func updateWindowHeight() {
        guard let window = NSApp.keyWindow else { return }

        let baseHeight: CGFloat = 70
        let resultsHeight: CGFloat = viewModel.searchQuery.isEmpty ? 0 : min(CGFloat(viewModel.results.count) * 50 + 120, 450)
        let newHeight = baseHeight + resultsHeight + (viewModel.searchQuery.isEmpty ? 0 : 12)

        var frame = window.frame
        let oldHeight = frame.height
        frame.size.height = newHeight
        frame.origin.y += (oldHeight - newHeight)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
}

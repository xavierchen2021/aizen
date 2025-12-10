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
        let panel = FileSearchPanel(worktreePath: worktreePath, onFileSelected: onFileSelected)
        self.init(window: panel)
        setupAppObservers()
    }

    deinit {
        cleanup()
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

    private func cleanup() {
        if let observer = appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            appDeactivationObserver = nil
        }
    }

    override func showWindow(_ sender: Any?) {
        guard let panel = window as? FileSearchPanel else { return }

        // Position on active screen
        positionPanel(panel)

        // Show panel and make it key to enable proper focus handling
        panel.makeKeyAndOrderFront(nil)

        // Ensure focus is possible by making panel the key window
        DispatchQueue.main.async {
            panel.makeKey()
        }
    }

    private func positionPanel(_ panel: FileSearchPanel) {
        // Use screen with mouse cursor for better UX
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame

        // Center horizontally, position near top
        let x = screenFrame.midX - panelFrame.width / 2
        let y = screenFrame.maxY - panelFrame.height - 100

        // Ensure panel stays on screen
        let adjustedX = max(screenFrame.minX, min(x, screenFrame.maxX - panelFrame.width))
        let adjustedY = max(screenFrame.minY, min(y, screenFrame.maxY - panelFrame.height))

        panel.setFrameOrigin(NSPoint(x: adjustedX, y: adjustedY))
    }

    func closeWindow() {
        cleanup()
        window?.close()
    }
}

class FileSearchPanel: NSPanel {
    init(worktreePath: String, onFileSelected: @escaping (String) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 70),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Make panel fully transparent - no window background at all
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = false
        self.level = .floating
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true

        // Remove any panel backdrop
        if #available(macOS 12.0, *) {
            // In newer macOS, explicitly disable content background
        }
        self.appearance = NSAppearance(named: .darkAqua)

        // Critical for NSPanel - proper keyboard focus handling
        self.becomesKeyOnlyIfNeeded = true
        self.isFloatingPanel = true

        let hostingView = NSHostingView(
            rootView: FileSearchWindowContent(
                worktreePath: worktreePath,
                onFileSelected: onFileSelected,
                onClose: { [weak self] in
                    self?.close()
                }
            )
        )

        // Ensure hosting view doesn't add any background
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

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
            viewModel.indexFiles()
            // Small delay to ensure view hierarchy and panel are fully ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: viewModel.results) { _ in
            updateWindowHeight()
        }
        // Keyboard shortcuts for file search - use hidden buttons for compatibility
        .background {
            Group {
                Button("") { viewModel.moveSelectionDown() }
                    .keyboardShortcut(.downArrow, modifiers: [])

                Button("") { viewModel.moveSelectionUp() }
                    .keyboardShortcut(.upArrow, modifiers: [])

                Button("") {
                    if let result = viewModel.getSelectedResult() {
                        selectFile(result)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])

                Button("") { onClose() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
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
                    ForEach(viewModel.results.indices, id: \.self) { index in
                        let result = viewModel.results[index]
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
                // No animation for smoother single-item navigation
                proxy.scrollTo(newIndex, anchor: .top)
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

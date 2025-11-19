//
//  FileSearchView.swift
//  aizen
//
//  Created on 2025-11-19.
//

import SwiftUI
import AppKit

struct FileSearchView: View {
    let worktreePath: String
    @Binding var isPresented: Bool
    let onFileSelected: (String) -> Void

    @StateObject private var viewModel: FileSearchViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var eventMonitor: Any?

    init(worktreePath: String, isPresented: Binding<Bool>, onFileSelected: @escaping (String) -> Void) {
        self.worktreePath = worktreePath
        self._isPresented = isPresented
        self.onFileSelected = onFileSelected
        self._viewModel = StateObject(wrappedValue: FileSearchViewModel(worktreePath: worktreePath))
    }

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                // Search input - circular/pill shaped
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))

                    TextField("Search files...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                )
                .frame(width: 560)

                // Results - only show when typing
                if !viewModel.searchQuery.isEmpty {
                    resultsCard
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 120)
        }
        .onAppear {
            isSearchFocused = true
            viewModel.indexFiles()
            setupKeyboardMonitoring()
        }
        .onDisappear {
            removeKeyboardMonitoring()
        }
        .onChange(of: viewModel.searchQuery) { _ in
            viewModel.performSearch()
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
        .frame(width: 560)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 15)
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
        .padding(.vertical, 40)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No files found")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 400)
            .onChange(of: viewModel.selectedIndex) { newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func resultRow(result: FileSearchResult, index: Int, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            FileIconView(path: result.path, size: 18)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .primary)

                Text(result.relativePath)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
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
                isPresented = false
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
        isPresented = false
    }
}

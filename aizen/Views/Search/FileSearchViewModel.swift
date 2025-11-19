//
//  FileSearchViewModel.swift
//  aizen
//
//  Created on 2025-11-19.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class FileSearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var results: [FileSearchResult] = []
    @Published var selectedIndex = 0
    @Published var isIndexing = false

    private let searchService = FileSearchService.shared
    private let worktreePath: String
    private var allResults: [FileSearchIndexResult] = []
    private var searchTask: Task<Void, Never>?

    init(worktreePath: String) {
        self.worktreePath = worktreePath
    }

    // Index files on appear
    func indexFiles() {
        guard !isIndexing else { return }

        isIndexing = true

        Task {
            do {
                allResults = try await searchService.indexDirectory(worktreePath)
                // Show recent files initially
                let initialResults = await searchService.search(
                    query: "",
                    in: allResults,
                    worktreePath: worktreePath
                )
                results = mapToDisplayResults(initialResults)
                isIndexing = false
            } catch {
                print("Failed to index directory: \(error)")
                isIndexing = false
            }
        }
    }

    // Perform search with debouncing
    func performSearch() {
        // Cancel previous search
        searchTask?.cancel()

        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

            guard !Task.isCancelled else { return }

            let searchResults = await searchService.search(
                query: searchQuery,
                in: allResults,
                worktreePath: worktreePath
            )

            guard !Task.isCancelled else { return }

            results = Array(mapToDisplayResults(searchResults).prefix(50))
            selectedIndex = 0
        }
    }

    // Navigate selection
    func moveSelectionUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveSelectionDown() {
        if selectedIndex < results.count - 1 {
            selectedIndex += 1
        }
    }

    // Get selected result
    func getSelectedResult() -> FileSearchResult? {
        guard selectedIndex < results.count else { return nil }
        return results[selectedIndex]
    }

    // Track opened file
    func trackFileOpen(_ path: String) {
        Task {
            await searchService.addRecentFile(path, worktreePath: worktreePath)
        }
    }

    // Clear cache
    func clearCache() {
        Task {
            await searchService.clearCache(for: worktreePath)
        }
    }

    // MARK: - Helpers

    private func mapToDisplayResults(_ entries: [FileSearchIndexResult]) -> [FileSearchResult] {
        entries.map {
            FileSearchResult(
                path: $0.path,
                relativePath: $0.relativePath,
                isDirectory: $0.isDirectory,
                matchScore: $0.matchScore
            )
        }
    }
}

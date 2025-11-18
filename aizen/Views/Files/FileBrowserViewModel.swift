//
//  FileBrowserViewModel.swift
//  aizen
//
//  View model for file browser state management
//

import Foundation
import SwiftUI
import Combine
import CoreData
import AppKit

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
}

struct OpenFileInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let path: String
    var content: String
    var hasUnsavedChanges: Bool

    init(id: UUID = UUID(), name: String, path: String, content: String, hasUnsavedChanges: Bool = false) {
        self.id = id
        self.name = name
        self.path = path
        self.content = content
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    static func == (lhs: OpenFileInfo, rhs: OpenFileInfo) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: String
    @Published var openFiles: [OpenFileInfo] = []
    @Published var selectedFileId: UUID?
    @Published var expandedPaths: Set<String> = []

    private let worktree: Worktree
    private let viewContext: NSManagedObjectContext
    private var session: FileBrowserSession?

    init(worktree: Worktree, context: NSManagedObjectContext) {
        self.worktree = worktree
        self.viewContext = context
        self.currentPath = worktree.path ?? ""

        // Load or create session
        loadSession()
    }

    private func loadSession() {
        // Try to get existing session from worktree
        if let existingSession = worktree.fileBrowserSession {
            self.session = existingSession

            // Restore state from session
            if let currentPath = existingSession.currentPath {
                self.currentPath = currentPath
            }

            if let expandedPathsArray = existingSession.value(forKey: "expandedPaths") as? [String] {
                self.expandedPaths = Set(expandedPathsArray)
            }

            if let selectedPath = existingSession.selectedFilePath {
                // Restore selected file if it was open
                if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String],
                   openPathsArray.contains(selectedPath) {
                    // Will be restored when files are reopened
                }
            }

            // Restore open files
            if let openPathsArray = existingSession.value(forKey: "openFilesPaths") as? [String] {
                Task {
                    for path in openPathsArray {
                        await openFile(path: path)
                    }

                    // Restore selection after files are opened
                    if let selectedPath = existingSession.selectedFilePath,
                       let selectedFile = openFiles.first(where: { $0.path == selectedPath }) {
                        selectedFileId = selectedFile.id
                    }
                }
            }
        } else {
            // Create new session
            let newSession = FileBrowserSession(context: viewContext)
            newSession.id = UUID()
            newSession.currentPath = currentPath
            newSession.setValue([], forKey: "expandedPaths")
            newSession.setValue([], forKey: "openFilesPaths")
            newSession.worktree = worktree
            self.session = newSession

            saveSession()
        }
    }

    private func saveSession() {
        guard let session = session else { return }

        session.currentPath = currentPath
        session.setValue(Array(expandedPaths), forKey: "expandedPaths")
        session.setValue(openFiles.map { $0.path }, forKey: "openFilesPaths")
        session.selectedFilePath = openFiles.first(where: { $0.id == selectedFileId })?.path

        do {
            try viewContext.save()
        } catch {
            print("Error saving FileBrowserSession: \(error)")
        }
    }

    func listDirectory(path: String) throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return contents.map { fileURL in
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileItem(
                name: fileURL.lastPathComponent,
                path: fileURL.path,
                isDirectory: isDir
            )
        }.sorted { item1, item2 in
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }

    func openFile(path: String) async {
        // Check if already open
        if let existing = openFiles.first(where: { $0.path == path }) {
            selectedFileId = existing.id
            return
        }

        // Load file content
        let fileURL = URL(fileURLWithPath: path)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }

        let fileInfo = OpenFileInfo(
            name: fileURL.lastPathComponent,
            path: path,
            content: content
        )

        openFiles.append(fileInfo)
        selectedFileId = fileInfo.id
        saveSession()
    }

    func closeFile(id: UUID) {
        openFiles.removeAll { $0.id == id }
        if selectedFileId == id {
            selectedFileId = openFiles.last?.id
        }
        saveSession()
    }

    func saveFile(id: UUID) throws {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        let file = openFiles[index]
        try file.content.write(toFile: file.path, atomically: true, encoding: .utf8)
        openFiles[index].hasUnsavedChanges = false
    }

    func updateFileContent(id: UUID, content: String) {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return
        }

        openFiles[index].content = content
        openFiles[index].hasUnsavedChanges = true
    }

    func toggleExpanded(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        saveSession()
    }

    func isExpanded(path: String) -> Bool {
        expandedPaths.contains(path)
    }

    // MARK: - File Operations

    private let fileService = FileService()

    func createNewFile(parentPath: String, name: String) async {
        let filePath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createFile(at: filePath)
            ToastManager.shared.show("Created \(name)", type: .success)

            // Refresh the parent directory by toggling expansion
            if expandedPaths.contains(parentPath) {
                expandedPaths.remove(parentPath)
                expandedPaths.insert(parentPath)
            }

            // Open the new file
            await openFile(path: filePath)
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func createNewFolder(parentPath: String, name: String) async {
        let folderPath = (parentPath as NSString).appendingPathComponent(name)

        do {
            try await fileService.createDirectory(at: folderPath)
            ToastManager.shared.show("Created folder \(name)", type: .success)

            // Refresh the parent directory
            if expandedPaths.contains(parentPath) {
                expandedPaths.remove(parentPath)
                expandedPaths.insert(parentPath)
            }

            // Auto-expand the newly created folder
            expandedPaths.insert(folderPath)
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func renameItem(oldPath: String, newName: String) async {
        let parentPath = (oldPath as NSString).deletingLastPathComponent
        let newPath = (parentPath as NSString).appendingPathComponent(newName)

        do {
            try await fileService.renameItem(from: oldPath, to: newPath)
            ToastManager.shared.show("Renamed to \(newName)", type: .success)

            // If file was open, update its info
            if let index = openFiles.firstIndex(where: { $0.path == oldPath }) {
                let fileInfo = openFiles[index]
                openFiles[index] = OpenFileInfo(
                    id: fileInfo.id,
                    name: newName,
                    path: newPath,
                    content: fileInfo.content,
                    hasUnsavedChanges: fileInfo.hasUnsavedChanges
                )
            }

            // Refresh parent directory
            if expandedPaths.contains(parentPath) {
                expandedPaths.remove(parentPath)
                expandedPaths.insert(parentPath)
            }

            // If it was a directory that was expanded, update its path in expandedPaths
            if expandedPaths.contains(oldPath) {
                expandedPaths.remove(oldPath)
                expandedPaths.insert(newPath)
            }

            saveSession()
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func deleteItem(path: String) async {
        let fileName = (path as NSString).lastPathComponent
        let parentPath = (path as NSString).deletingLastPathComponent

        do {
            try await fileService.deleteItem(at: path)
            ToastManager.shared.show("Deleted \(fileName)", type: .success)

            // Close file if it was open
            if let openFile = openFiles.first(where: { $0.path == path }) {
                closeFile(id: openFile.id)
            }

            // Remove from expanded paths if it was a directory
            expandedPaths.remove(path)

            // Refresh parent directory
            if expandedPaths.contains(parentPath) {
                expandedPaths.remove(parentPath)
                expandedPaths.insert(parentPath)
            }
        } catch {
            ToastManager.shared.show(error.localizedDescription, type: .error)
        }
    }

    func copyPathToClipboard(path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
        ToastManager.shared.show("Path copied to clipboard", type: .success)
    }

    func revealInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

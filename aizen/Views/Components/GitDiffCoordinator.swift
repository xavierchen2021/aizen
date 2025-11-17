//
//  GitDiffCoordinator.swift
//  aizen
//
//  Coordinator to pass git diff data to the editor gutter
//

import Foundation
import AppKit
import CodeEditSourceEditor
import CodeEditTextView

typealias GitDiffLineStatus = CodeEditSourceEditor.GitDiffLineStatus

/// Coordinator that updates the gutter with git diff indicators
class GitDiffCoordinator: TextViewCoordinator {
    var gitDiffStatus: [Int: GitDiffLineStatus] = [:] {
        didSet {
            updateGutterDiffStatus()
        }
    }

    private weak var textViewController: TextViewController?

    func prepareCoordinator(controller: TextViewController) {
        self.textViewController = controller
        updateGutterDiffStatus()
    }

    func textViewDidChangeText(_ notification: Notification) {
        // Could reload git diff here if needed
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        // Not needed for git diff
    }

    private func updateGutterDiffStatus() {
        textViewController?.gutterView?.gitDiffStatus = gitDiffStatus
    }
}

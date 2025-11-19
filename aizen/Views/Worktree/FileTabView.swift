//
//  FileTabView.swift
//  aizen
//
//  File browser tab for worktree
//

import SwiftUI
import CoreData

struct FileTabView: View {
    let worktree: Worktree
    @Binding var fileToOpenFromSearch: String?
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if worktree.path != nil {
            FileBrowserSessionView(
                worktree: worktree,
                context: viewContext,
                fileToOpenFromSearch: $fileToOpenFromSearch
            )
        } else {
            VStack {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Worktree path not available")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

//
//  TaskItemView.swift
//  aizen
//
//  Individual task item view
//

import SwiftUI

struct TaskItemView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onCopyMarkdown: () -> Void
    let onExecute: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and actions
            HStack {
                Text(task.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if isHovering {
                    HStack(spacing: 8) {
                        Button {
                            onEdit()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("编辑")
                        
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                    }
                }
            }
            
            // Description
            if let desc = task.taskDescription, !desc.isEmpty {
                Text(desc)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            // Resources
            if let res = task.resources, !res.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    
                    Text(res)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            
            // Custom prefix indicator
            if let prefix = task.customPrefix, !prefix.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 11))
                    Text("自定义前缀")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button {
                    onCopyMarkdown()
                } label: {
                    Label("tasks.copyAsMarkdown", systemImage: "doc.on.doc")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    onExecute()
                } label: {
                    Label("tasks.execute", systemImage: "play.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

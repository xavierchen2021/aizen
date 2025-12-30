//
//  TaskEditorView.swift
//  aizen
//
//  Task editor sheet view
//

import SwiftUI

struct TaskEditorView: View {
    let task: TaskItem?
    let onSave: (String, String, String, String, String) -> Void
    let onCancel: () -> Void
    
    @State private var title: String
    @State private var taskDescription: String
    @State private var resources: String
    @State private var customPrefix: String
    @State private var markdownTemplate: String
    
    init(task: TaskItem?, onSave: @escaping (String, String, String, String, String) -> Void, onCancel: @escaping () -> Void) {
        self.task = task
        self.onSave = onSave
        self.onCancel = onCancel
        
        _title = State(initialValue: task?.title ?? "")
        _taskDescription = State(initialValue: task?.taskDescription ?? "")
        _resources = State(initialValue: task?.resources ?? "")
        _customPrefix = State(initialValue: task?.customPrefix ?? "")
        _markdownTemplate = State(initialValue: task?.markdownTemplate ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(task == nil ? "tasks.editor.create" : "tasks.editor.edit")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("tasks.title")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField("tasks.title.placeholder", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("tasks.description")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextEditor(text: $taskDescription)
                            .font(.body)
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                    
                    // Resources
                    VStack(alignment: .leading, spacing: 8) {
                        Text("tasks.resources")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextEditor(text: $resources)
                            .font(.body)
                            .frame(minHeight: 80)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                    
                    // Custom Prefix
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("tasks.customPrefix")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .help("tasks.customPrefix.hint")
                        }
                        
                        TextEditor(text: $customPrefix)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 60)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                    }
                    
                    // Markdown Template
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("tasks.markdownTemplate")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .help("tasks.markdownTemplate.hint")
                        }
                        
                        TextEditor(text: $markdownTemplate)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                            )
                        
                        Text("tasks.markdownTemplate.variables")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button {
                    onCancel()
                } label: {
                    Text("common.cancel")
                        .frame(minWidth: 80)
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    onSave(title, taskDescription, resources, customPrefix, markdownTemplate)
                } label: {
                    Text("common.save")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 600, height: 650)
    }
}

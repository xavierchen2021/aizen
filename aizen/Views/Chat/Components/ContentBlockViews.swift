//  ContentBlockViews.swift
//  aizen
//
//  Content block rendering views for chat messages
//

import SwiftUI

// MARK: - Content Block View

struct ContentBlockView: View {
    let block: ContentBlock
    @State private var isCopied: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                contentTypeLabel
                Spacer()
                copyButton
            }

            contentBody
        }
        .padding(8)
        .background(Color(.textBackgroundColor))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var contentTypeLabel: some View {
        Group {
            switch block {
            case .text:
                Label(String(localized: "chat.content.textOutput"), systemImage: "text.alignleft")
            case .image:
                Label(String(localized: "chat.content.image"), systemImage: "photo")
            case .resource:
                Label(String(localized: "chat.content.resource"), systemImage: "doc.badge.gearshape")
            case .resourceLink:
                Label(String(localized: "chat.content.resourceLink"), systemImage: "link.circle")
            case .audio:
                Label(String(localized: "chat.content.audio"), systemImage: "waveform")
            }
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
    }

    private var copyButton: some View {
        Button(action: copyContent) {
            HStack(spacing: 3) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                Text(isCopied ? String(localized: "chat.content.copied") : String(localized: "chat.content.copy"))
            }
            .font(.system(size: 10))
            .foregroundColor(isCopied ? .green : .blue)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contentBody: some View {
        switch block {
        case .text(let content):
            TextContentView(text: content.text)
        case .image(let content):
            ACPImageView(data: content.data, mimeType: content.mimeType)
        case .resource(let content):
            resourceView(for: content.resource)
        case .audio(let content):
            Text(String(format: String(localized: "chat.content.audioType"), content.mimeType))
                .foregroundColor(.secondary)
        case .resourceLink(let content):
            VStack(alignment: .leading, spacing: 4) {
                if let title = content.title {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(content.uri)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    private func copyContent() {
        let textToCopy: String

        switch block {
        case .text(let content):
            textToCopy = content.text
        case .image:
            textToCopy = String(localized: "chat.content.imageContent")
        case .resource(let content):
            let uri: String
            let text: String?
            switch content.resource {
            case .text(let textResource):
                uri = textResource.uri
                text = textResource.text
            case .blob(let blobResource):
                uri = blobResource.uri
                text = nil
            }
            textToCopy = text ?? uri
        case .resourceLink(let content):
            textToCopy = content.uri
        case .audio(let content):
            textToCopy = String(format: String(localized: "chat.content.audioContent"), content.mimeType)
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)

        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    @ViewBuilder
    private func resourceView(for resource: EmbeddedResourceType) -> some View {
        switch resource {
        case .text(let textResource):
            ACPResourceView(uri: textResource.uri, mimeType: textResource.mimeType, text: textResource.text)
        case .blob(let blobResource):
            ACPResourceView(uri: blobResource.uri, mimeType: blobResource.mimeType, text: nil)
        }
    }
}

// MARK: - Text Content View

struct TextContentView: View {
    let text: String

    var body: some View {
        ScrollView {
            if isDiff {
                DiffContentView(text: text)
            } else if isTerminalOutput {
                TerminalContentView(text: text)
            } else {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxHeight: 300)
    }

    private var isDiff: Bool {
        text.contains("+++") || text.contains("---") ||
        text.split(separator: "\n").contains { line in
            line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix("@@")
        }
    }

    private var isTerminalOutput: Bool {
        text.contains("$") && (text.contains("\n") || text.count > 50)
    }
}

// MARK: - Diff Content View

struct DiffContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.self) { line in
                diffLine(line)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func diffLine(_ line: String) -> some View {
        Text(line)
            .foregroundColor(lineColor(for: line))
            .background(lineBackground(for: line))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return .green
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return .red
        } else if line.hasPrefix("@@") {
            return .blue
        }
        return .primary
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") {
            return Color.green.opacity(0.1)
        } else if line.hasPrefix("-") && !line.hasPrefix("---") {
            return Color.red.opacity(0.1)
        }
        return Color.clear
    }
}

// MARK: - Terminal Content View

struct TerminalContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .foregroundColor(lineColor(for: line))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.black.opacity(0.85))
        .cornerRadius(3)
    }

    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func lineColor(for line: String) -> Color {
        let lowercased = line.lowercased()
        if lowercased.contains("error") {
            return .red
        } else if lowercased.contains("warn") {
            return .yellow
        } else if lowercased.contains("success") || line.contains("✓") {
            return .green
        } else if line.hasPrefix("$") || line.hasPrefix(">") {
            return .cyan
        }
        return .white
    }
}

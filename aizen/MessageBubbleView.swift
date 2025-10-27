//
//  MessageBubbleView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import Markdown
import HighlightSwift

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// SwiftUI view for rendering chat messages with role-based styling
struct MessageBubbleView: View {
    let message: MessageItem
    let agentName: String?

    @State private var showCopyConfirmation = false

    private var alignment: HorizontalAlignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    private var bubbleAlignment: Alignment {
        switch message.role {
        case .user:
            return .trailing
        case .agent:
            return .leading
        case .system:
            return .center
        }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            if message.role == .agent, let name = agentName {
                HStack(spacing: 4) {
                    AgentIconView(agent: name, size: 14)
                    Text(name.capitalized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                if message.role == .user {
                    Spacer(minLength: 100)
                }

                if message.role == .system {
                    Spacer()
                }

                VStack(alignment: message.role == .system ? .center : .leading, spacing: 6) {
                    MessageContentView(content: message.content, isComplete: message.isComplete)

                    // Render attachment chips for non-text content blocks
                    if message.contentBlocks.count > 1 {
                        let attachmentBlocks = Array(message.contentBlocks.dropFirst())
                        HStack(spacing: 6) {
                            ForEach(Array(attachmentBlocks.enumerated()), id: \.offset) { index, block in
                                AttachmentChipView(block: block)
                            }
                        }
                        .padding(.top, 4)
                    }

                    if message.role != .system {
                        HStack(spacing: 8) {
                            Text(formatTimestamp(message.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            if message.role == .user {
                                Spacer()

                                Button(action: copyMessage) {
                                    Image(systemName: showCopyConfirmation ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(showCopyConfirmation ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy message")
                            }
                        }
                    }
                }
                .if(message.role == .user) { view in
                    view
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            backgroundView
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .fixedSize(horizontal: message.role != .agent, vertical: false)
                .frame(maxWidth: message.role == .user ? 500 : .infinity, alignment: bubbleAlignment)

                if message.role == .agent {
                    Spacer(minLength: 100)
                }

                if message.role == .system {
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: bubbleAlignment)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95, anchor: bubbleAlignment == .trailing ? .bottomTrailing : .bottomLeading)
                .combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: message.id)
    }

    @ViewBuilder
    private var backgroundView: some View {
        // Only user messages have bubble background
        Color.clear
            .background(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
            }
    }

    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

}

// MARK: - Agent Badge

struct AgentBadge: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue)
            .clipShape(Capsule())
    }
}

// MARK: - Message Content View

struct MessageContentView: View {
    let content: String
    var isComplete: Bool = true

    var body: some View {
        if isComplete {
            MarkdownRenderedView(content: content)
        } else {
            // For incomplete messages, show plain text to avoid flickering from partial markdown
            Text(content)
                .textSelection(.enabled)
                .opacity(0.9)
        }
    }
}

// MARK: - Markdown Rendered View

struct MarkdownRenderedView: View {
    let content: String

    private var renderedBlocks: [MarkdownBlock] {
        let document = Document(parsing: content)
        return convertMarkdown(document)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .paragraph(let attributedText):
                    Text(attributedText)
                        .textSelection(.enabled)
                case .heading(let attributedText, let level):
                    Text(attributedText)
                        .font(fontForHeading(level: level))
                        .fontWeight(.bold)
                        .textSelection(.enabled)
                case .codeBlock(let code, let language):
                    CodeBlockView(code: code, language: language)
                case .list(let items, let isOrdered):
                    ForEach(Array(items.enumerated()), id: \.offset) { itemIndex, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text(isOrdered ? "\(itemIndex + 1)." : "•")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .textSelection(.enabled)
                        }
                    }
                case .blockQuote(let attributedText):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3)
                        Text(attributedText)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func convertMarkdown(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []

        for child in document.children {
            if let paragraph = child as? Paragraph {
                let attributedText = renderInlineContent(paragraph.children)
                blocks.append(.paragraph(attributedText))
            } else if let heading = child as? Heading {
                let attributedText = renderInlineContent(heading.children)
                blocks.append(.heading(attributedText, level: heading.level))
            } else if let codeBlock = child as? CodeBlock {
                blocks.append(.codeBlock(codeBlock.code, language: codeBlock.language))
            } else if let list = child as? UnorderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: false))
            } else if let list = child as? OrderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(.list(items, isOrdered: true))
            } else if let blockQuote = child as? BlockQuote {
                let text = renderBlockQuoteContent(blockQuote.children)
                blocks.append(.blockQuote(text))
            }
        }

        return blocks
    }

    private func renderInlineContent(_ inlineElements: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for element in inlineElements {
            if let text = element as? Markdown.Text {
                result += AttributedString(text.string)
            } else if let strong = element as? Strong {
                var boldText = renderInlineContent(strong.children)
                boldText.font = .body.bold()
                result += boldText
            } else if let emphasis = element as? Emphasis {
                var italicText = renderInlineContent(emphasis.children)
                italicText.font = .body.italic()
                result += italicText
            } else if let code = element as? InlineCode {
                var codeText = AttributedString(code.code)
                codeText.font = .system(.body, design: .monospaced)
                codeText.backgroundColor = Color(nsColor: .textBackgroundColor)
                result += codeText
            } else if let link = element as? Markdown.Link {
                var linkText = renderInlineContent(link.children)
                if let url = URL(string: link.destination ?? "") {
                    linkText.link = url
                }
                linkText.foregroundColor = Color.blue
                linkText.underlineStyle = .single
                result += linkText
            } else if let strikethrough = element as? Strikethrough {
                var strikethroughText = renderInlineContent(strikethrough.children)
                strikethroughText.strikethroughStyle = .single
                result += strikethroughText
            } else if let paragraph = element as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func renderBlockQuoteContent(_ children: some Sequence<Markup>) -> AttributedString {
        var result = AttributedString()

        for child in children {
            if let paragraph = child as? Paragraph {
                result += renderInlineContent(paragraph.children)
            }
        }

        return result
    }

    private func fontForHeading(level: Int) -> Font {
        switch level {
        case 1: return .largeTitle
        case 2: return .title
        case 3: return .title2
        case 4: return .title3
        case 5: return .headline
        default: return .body
        }
    }
}

// MARK: - Markdown Block Type

enum MarkdownBlock {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case codeBlock(String, language: String?)
    case list([AttributedString], isOrdered: Bool)
    case blockQuote(AttributedString)
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?

    @State private var showCopyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: copyCode) {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                if let lang = language,
                   !lang.isEmpty,
                   !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let highlightLang = LanguageDetection.highlightLanguageFromFence(lang) {
                    CodeText(code)
                        .highlightLanguage(highlightLang)
                        .codeTextColors(.theme(.github))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(code)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)

        withAnimation {
            showCopyConfirmation = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopyConfirmation = false
            }
        }
    }
}

// MARK: - Advanced Content Block View (for ContentBlock types from ACPTypes)

/// View builder for rendering ACPTypes ContentBlock with images and resources
struct ACPContentBlockView: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                contentView(for: block)
            }
        }
    }

    private func contentView(for block: ContentBlock) -> AnyView {
        switch block {
        case .text(let textContent):
            return AnyView(MessageContentView(content: textContent.text))

        case .image(let imageContent):
            return AnyView(ACPImageView(data: imageContent.data, mimeType: imageContent.mimeType))

        case .resource(let resourceContent):
            return AnyView(ACPResourceView(uri: resourceContent.resource.uri, mimeType: resourceContent.resource.mimeType, text: resourceContent.resource.text))

        case .audio(let audioContent):
            return AnyView(
                Text("Audio content: \(audioContent.mimeType)")
                    .foregroundColor(.secondary)
            )

        case .embeddedResource(let embeddedContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 8) {
                    Text("Embedded: \(embeddedContent.uri)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(0..<embeddedContent.content.count, id: \.self) { index in
                        contentView(for: embeddedContent.content[index])
                    }
                }
            )

        case .diff(let diffContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    if let path = diffContent.path {
                        Text("File: \(path)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("Diff content")
                        .font(.system(.body, design: .monospaced))
                }
            )

        case .terminalEmbed(let terminalContent):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terminal: \(terminalContent.command)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(terminalContent.output)
                        .font(.system(.body, design: .monospaced))
                    if let exitCode = terminalContent.exitCode {
                        Text("Exit code: \(exitCode)")
                            .font(.caption2)
                            .foregroundColor(exitCode == 0 ? .green : .red)
                    }
                }
            )
        }
    }
}

// MARK: - Attachment Chip View

struct AttachmentChipView: View {
    let block: ContentBlock
    @State private var showingContent = false

    var body: some View {
        Button {
            showingContent = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingContent) {
            AttachmentDetailView(block: block)
        }
    }

    private var iconName: String {
        switch block {
        case .resource:
            return "doc.fill"
        case .image:
            return "photo.fill"
        case .audio:
            return "waveform"
        case .embeddedResource:
            return "doc.badge.gearshape.fill"
        case .diff:
            return "doc.text.magnifyingglass"
        case .terminalEmbed:
            return "terminal.fill"
        default:
            return "doc.fill"
        }
    }

    private var fileName: String {
        switch block {
        case .resource(let content):
            // Extract filename from URI
            if let url = URL(string: content.resource.uri) {
                return url.lastPathComponent
            }
            return "File"
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        case .embeddedResource(let content):
            if let url = URL(string: content.uri) {
                return url.lastPathComponent
            }
            return "Resource"
        case .diff(let content):
            return content.path ?? "Diff"
        case .terminalEmbed:
            return "Terminal Output"
        default:
            return "Attachment"
        }
    }
}

// MARK: - Attachment Detail View

struct AttachmentDetailView: View {
    let block: ContentBlock
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Content
            ScrollView {
                ACPContentBlockView(blocks: [block])
                    .padding()
            }
        }
        .frame(width: 700, height: 500)
    }

    private var title: String {
        switch block {
        case .resource(let content):
            if let url = URL(string: content.resource.uri) {
                return url.lastPathComponent
            }
            return "File"
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        case .embeddedResource(let content):
            if let url = URL(string: content.uri) {
                return url.lastPathComponent
            }
            return "Resource"
        case .diff(let content):
            return content.path ?? "Diff"
        case .terminalEmbed:
            return "Terminal Output"
        default:
            return "Attachment"
        }
    }
}


// MARK: - Preview

#Preview("User Message") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "1",
                role: .user,
                content: "How do I implement a neural network in Swift?",
                timestamp: Date()
            ),
            agentName: nil
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("Agent Message with Code") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "2",
                role: .agent,
                content: """
                Here's a simple neural network implementation:

                ```swift
                class NeuralNetwork {
                    var weights: [[Double]]

                    init(layers: [Int]) {
                        self.weights = []
                    }
                }
                ```

                This creates the basic structure.
                """,
                timestamp: Date()
            ),
            agentName: "Claude"
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("System Message") {
    VStack {
        MessageBubbleView(
            message: MessageItem(
                id: "3",
                role: .system,
                content: "Session started with agent in /Users/user/project",
                timestamp: Date()
            ),
            agentName: nil
        )
    }
    .frame(width: 600)
    .padding()
}

#Preview("All Message Types") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubbleView(
                message: MessageItem(
                    id: "1",
                    role: .system,
                    content: "Session started",
                    timestamp: Date().addingTimeInterval(-300)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "2",
                    role: .user,
                    content: "Can you help me with git?",
                    timestamp: Date().addingTimeInterval(-240)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "3",
                    role: .agent,
                    content: "I can help with git commands. What do you need?",
                    timestamp: Date().addingTimeInterval(-180)
                ),
                agentName: "Claude"
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "4",
                    role: .user,
                    content: "Show me how to create a branch",
                    timestamp: Date().addingTimeInterval(-120)
                ),
                agentName: nil
            )

            MessageBubbleView(
                message: MessageItem(
                    id: "5",
                    role: .agent,
                    content: """
                    Create a new branch with:

                    ```bash
                    git checkout -b feature/new-feature
                    ```

                    This creates and switches to the new branch.
                    """,
                    timestamp: Date().addingTimeInterval(-60)
                ),
                agentName: "Claude"
            )
        }
        .padding()
    }
    .frame(width: 600, height: 800)
}

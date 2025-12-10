//
//  MarkdownContentView.swift
//  aizen
//
//  Markdown rendering components
//

import SwiftUI
import Markdown

// MARK: - Message Content View

struct MessageContentView: View {
    let content: String
    var isComplete: Bool = true

    var body: some View {
        MarkdownRenderedView(content: content, isStreaming: !isComplete)
    }
}

// MARK: - Markdown Rendered View

struct MarkdownRenderedView: View {
    let content: String
    var isStreaming: Bool = false

    @State private var cachedBlocks: [MarkdownBlock] = []
    @State private var cachedContentHash: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(cachedBlocks) { block in
                MarkdownBlockView(
                    block: block,
                    isStreaming: isStreaming,
                    isLast: block.id == cachedBlocks.last?.id
                )
            }
        }
        .onAppear {
            updateCacheIfNeeded()
        }
        .onChange(of: content) { _ in
            updateCacheIfNeeded()
        }
    }

    private func updateCacheIfNeeded() {
        let contentHash = content.hashValue
        guard cachedContentHash != contentHash else { return }
        let document = Document(parsing: content)
        cachedBlocks = convertMarkdown(document)
        cachedContentHash = contentHash
    }

    private func convertMarkdown(_ document: Document) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = 0

        for child in document.children {
            if let paragraph = child as? Paragraph {
                // Check if paragraph contains only images (badges case)
                let images = extractImagesFromParagraph(paragraph)

                // Check if there's any text content besides images
                var hasText = false
                for child in paragraph.children {
                    if let text = child as? Markdown.Text, !text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hasText = true
                        break
                    }
                    if child is Markdown.SoftBreak || child is Markdown.LineBreak {
                        continue
                    }
                    // If it's not an image or link containing image, it's other content
                    if !(child is Markdown.Image) && !(child is Markdown.Link) {
                        hasText = true
                        break
                    }
                }

                if !images.isEmpty && !hasText {
                    // Multiple images in same paragraph - render as image row
                    let imageData = images.compactMap { image -> (url: String, alt: String?)? in
                        if case .imageRow(let items) = image.type, let first = items.first {
                            return first
                        }
                        if case .image(let url, let alt) = image.type {
                            return (url: url, alt: alt)
                        }
                        return nil
                    }
                    blocks.append(MarkdownBlock(.imageRow(imageData), index: index))
                } else {
                    let attributedText = renderInlineContent(paragraph.children)
                    if !attributedText.characters.isEmpty {
                        blocks.append(MarkdownBlock(.paragraph(attributedText), index: index))
                    }
                }
            } else if let heading = child as? Heading {
                let attributedText = renderInlineContent(heading.children)
                blocks.append(MarkdownBlock(.heading(attributedText, level: heading.level), index: index))
            } else if let codeBlock = child as? CodeBlock {
                // Check for mermaid diagram
                if codeBlock.language?.lowercased() == "mermaid" {
                    blocks.append(MarkdownBlock(.mermaidDiagram(codeBlock.code), index: index))
                } else {
                    blocks.append(MarkdownBlock(.codeBlock(codeBlock.code, language: codeBlock.language), index: index))
                }
            } else if let list = child as? UnorderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(MarkdownBlock(.list(items, isOrdered: false), index: index))
            } else if let list = child as? OrderedList {
                let items = Array(list.listItems.map { renderInlineContent($0.children) })
                blocks.append(MarkdownBlock(.list(items, isOrdered: true), index: index))
            } else if let blockQuote = child as? BlockQuote {
                let text = renderBlockQuoteContent(blockQuote.children)
                blocks.append(MarkdownBlock(.blockQuote(text), index: index))
            } else if let table = child as? Markdown.Table {
                let headerCells = table.head.cells.map { renderInlineContent($0.children) }
                var bodyRows: [[AttributedString]] = []
                for row in table.body.rows {
                    let rowCells = row.cells.map { renderInlineContent($0.children) }
                    bodyRows.append(Array(rowCells))
                }
                blocks.append(MarkdownBlock(.table(header: Array(headerCells), rows: bodyRows, alignments: table.columnAlignments), index: index))
            }
            index += 1
        }

        return blocks
    }

    private func extractImagesFromParagraph(_ paragraph: Paragraph) -> [MarkdownBlock] {
        var images: [MarkdownBlock] = []
        var imgIndex = 0

        for child in paragraph.children {
            // Direct image
            if let image = child as? Markdown.Image {
                images.append(MarkdownBlock(.image(url: image.source ?? "", alt: extractImageAlt(image)), index: imgIndex))
                imgIndex += 1
            }
            // Image wrapped in link (like badges)
            else if let link = child as? Markdown.Link {
                for linkChild in link.children {
                    if let image = linkChild as? Markdown.Image {
                        images.append(MarkdownBlock(.image(url: image.source ?? "", alt: extractImageAlt(image)), index: imgIndex))
                        imgIndex += 1
                    }
                }
            }
        }

        return images
    }

    private func extractImageAlt(_ image: Markdown.Image) -> String? {
        // Extract alt text from image children
        var alt = ""
        for child in image.children {
            if let text = child as? Markdown.Text {
                alt += text.string
            }
        }
        return alt.isEmpty ? nil : alt
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
}

// MARK: - Markdown Block View

/// Individual block renderer with stable identity
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    var isStreaming: Bool = false
    var isLast: Bool = false

    var body: some View {
        switch block.type {
        case .paragraph(let attributedText):
            Text(attributedText)
                .textSelection(.enabled)
                .opacity(isStreaming && isLast ? 0.9 : 1.0)
        case .heading(let attributedText, let level):
            Text(attributedText)
                .font(fontForHeading(level: level))
                .fontWeight(.bold)
                .textSelection(.enabled)
        case .codeBlock(let code, let language):
            CodeBlockView(code: code, language: language)
        case .list(let items, let isOrdered):
            MarkdownListView(items: items, isOrdered: isOrdered)
        case .blockQuote(let attributedText):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 3)
                Text(attributedText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .image(let url, let alt):
            MarkdownImageView(url: url, alt: alt)
        case .imageRow(let images):
            MarkdownImageRowView(images: images)
        case .mermaidDiagram(let code):
            MermaidDiagramView(code: code)
                .frame(height: 400)
        case .table(let header, let rows, let alignments):
            MarkdownTableView(header: header, rows: rows, alignments: alignments)
        }
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

// MARK: - List Item Wrapper for Stable IDs

struct ListItemWrapper: Identifiable {
    let id: String
    let index: Int
    let text: AttributedString

    init(index: Int, text: AttributedString) {
        self.index = index
        self.text = text
        // Convert AttributedString characters to String for hashing
        let textPrefix = String(text.characters.prefix(50))
        self.id = "li-\(index)-\(textPrefix.hashValue)"
    }
}

struct MarkdownListView: View {
    let items: [AttributedString]
    let isOrdered: Bool

    private var wrappedItems: [ListItemWrapper] {
        items.enumerated().map { ListItemWrapper(index: $0.offset, text: $0.element) }
    }

    var body: some View {
        ForEach(wrappedItems) { item in
            HStack(alignment: .top, spacing: 8) {
                Text(isOrdered ? "\(item.index + 1)." : "•")
                    .foregroundStyle(.secondary)
                Text(item.text)
                    .textSelection(.enabled)
            }
        }
    }
}

// MARK: - Image Row with Stable IDs

struct ImageRowItem: Identifiable {
    let id: String
    let url: String
    let alt: String?

    init(index: Int, url: String, alt: String?) {
        self.url = url
        self.alt = alt
        self.id = "imgrow-item-\(index)-\(url.hashValue)"
    }
}

struct MarkdownImageRowView: View {
    let images: [(url: String, alt: String?)]

    private var wrappedImages: [ImageRowItem] {
        images.enumerated().map { ImageRowItem(index: $0.offset, url: $0.element.url, alt: $0.element.alt) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(wrappedImages) { item in
                MarkdownImageView(url: item.url, alt: item.alt)
            }
        }
    }
}

// MARK: - Markdown Block Type

/// Markdown block with stable ID for efficient SwiftUI diffing
struct MarkdownBlock: Identifiable {
    let id: String
    let type: MarkdownBlockType

    init(_ type: MarkdownBlockType, index: Int = 0) {
        self.type = type
        self.id = Self.generateId(for: type, index: index)
    }

    /// Generate stable ID based on content (uses hash for efficiency)
    private static func generateId(for type: MarkdownBlockType, index: Int) -> String {
        switch type {
        case .paragraph(let text):
            // Use prefix hash for paragraphs to handle streaming updates
            let contentHash = String(text.characters.prefix(100)).hashValue
            return "p-\(index)-\(contentHash)"
        case .heading(let text, let level):
            let textHash = String(text.characters).hashValue
            return "h\(level)-\(index)-\(textHash)"
        case .codeBlock(let code, let lang):
            // Use prefix hash for code blocks (can be large)
            let codeHash = String(code.prefix(200)).hashValue
            return "code-\(index)-\(codeHash)-\(lang ?? "none")"
        case .list(let items, let ordered):
            let itemsHash = items.count > 0 ? String(items.first!.characters.prefix(50)).hashValue : 0
            return "list-\(ordered)-\(index)-\(items.count)-\(itemsHash)"
        case .blockQuote(let text):
            let textHash = String(text.characters).hashValue
            return "quote-\(index)-\(textHash)"
        case .image(let url, _):
            return "img-\(index)-\(url.hashValue)"
        case .imageRow(let images):
            let firstHash = images.first?.url.hashValue ?? 0
            return "imgrow-\(index)-\(images.count)-\(firstHash)"
        case .mermaidDiagram(let code):
            return "mermaid-\(index)-\(code.hashValue)"
        case .table(let header, let rows, _):
            return "table-\(index)-\(header.count)x\(rows.count)"
        }
    }
}

enum MarkdownBlockType {
    case paragraph(AttributedString)
    case heading(AttributedString, level: Int)
    case codeBlock(String, language: String?)
    case list([AttributedString], isOrdered: Bool)
    case blockQuote(AttributedString)
    case image(url: String, alt: String?)
    case imageRow([(url: String, alt: String?)])
    case mermaidDiagram(String)
    case table(header: [AttributedString], rows: [[AttributedString]], alignments: [Markdown.Table.ColumnAlignment?])
}

// MARK: - Markdown Image View

struct MarkdownImageView: View {
    let url: String
    let alt: String?

    @State private var image: NSImage?
    @State private var isLoading = true
    @State private var error: String?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: min(image.size.width, 600), height: min(image.size.height, 400))
                    .cornerRadius(4)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let error = error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Failed to load image")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let alt = alt, !alt.isEmpty {
                            Text(alt)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            // Start loading only if not already loaded
            guard loadTask == nil && image == nil else { return }
            loadTask = Task {
                await loadImage()
            }
        }
        .onDisappear {
            // Cancel loading when view disappears (scrolled off-screen)
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func loadImage() async {
        guard let imageURL = URL(string: url) else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        // Check for cancellation before starting
        guard !Task.isCancelled else { return }

        // Check if it's a local file path
        if imageURL.scheme == nil || imageURL.scheme == "file" {
            // Local file
            if let nsImage = NSImage(contentsOfFile: imageURL.path) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.image = nsImage
                    self.isLoading = false
                }
            } else {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = "File not found"
                    self.isLoading = false
                }
            }
        } else {
            // Remote URL
            do {
                let (data, _) = try await URLSession.shared.data(from: imageURL)
                guard !Task.isCancelled else { return }
                if let nsImage = NSImage(data: data) {
                    await MainActor.run {
                        self.image = nsImage
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.error = "Invalid image data"
                        self.isLoading = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Markdown Table View

struct TableCellWrapper: Identifiable {
    let id: String
    let colIndex: Int
    let text: AttributedString

    init(colIndex: Int, text: AttributedString, rowIndex: Int = -1) {
        self.colIndex = colIndex
        self.text = text
        let textPrefix = String(text.characters.prefix(20))
        self.id = "cell-\(rowIndex)-\(colIndex)-\(textPrefix.hashValue)"
    }
}

struct TableRowWrapper: Identifiable {
    let id: String
    let rowIndex: Int
    let cells: [TableCellWrapper]

    init(rowIndex: Int, cells: [AttributedString]) {
        self.rowIndex = rowIndex
        self.cells = cells.enumerated().map { TableCellWrapper(colIndex: $0.offset, text: $0.element, rowIndex: rowIndex) }
        self.id = "row-\(rowIndex)-\(cells.count)"
    }
}

struct MarkdownTableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    let alignments: [Markdown.Table.ColumnAlignment?]

    private var wrappedHeader: [TableCellWrapper] {
        header.enumerated().map { TableCellWrapper(colIndex: $0.offset, text: $0.element, rowIndex: -1) }
    }

    private var wrappedRows: [TableRowWrapper] {
        rows.enumerated().map { TableRowWrapper(rowIndex: $0.offset, cells: $0.element) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(wrappedHeader) { cell in
                        Text(cell.text)
                            .fontWeight(.semibold)
                            .frame(minWidth: 80, alignment: alignment(for: cell.colIndex))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5))

                Divider()

                // Body rows
                ForEach(wrappedRows) { row in
                    HStack(spacing: 0) {
                        ForEach(row.cells) { cell in
                            Text(cell.text)
                                .frame(minWidth: 80, alignment: alignment(for: cell.colIndex))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(row.rowIndex % 2 == 1 ? Color(nsColor: .textBackgroundColor).opacity(0.2) : Color.clear)
                }
            }
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.1))
        .cornerRadius(6)
    }

    private func alignment(for column: Int) -> Alignment {
        guard column < alignments.count, let align = alignments[column] else {
            return .leading
        }
        switch align {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

// MARK: - Mermaid Diagram View

import WebKit

struct MermaidDiagramView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <script type="module">
                    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
                    mermaid.initialize({
                        startOnLoad: true,
                        theme: 'dark',
                        themeVariables: {
                            darkMode: true,
                            background: 'transparent',
                            mainBkg: 'transparent',
                            primaryColor: '#89b4fa',
                            primaryTextColor: '#cdd6f4',
                            primaryBorderColor: '#89b4fa',
                            lineColor: '#6c7086',
                            secondaryColor: '#f5c2e7',
                            tertiaryColor: '#94e2d5',
                            fontSize: '14px',
                            nodeBorder: '#6c7086',
                            clusterBkg: 'transparent',
                            clusterBorder: '#6c7086',
                            defaultLinkColor: '#6c7086',
                            titleColor: '#cdd6f4',
                            edgeLabelBackground: 'transparent',
                            nodeTextColor: '#cdd6f4'
                        }
                    });
                </script>
                <style>
                    body {
                        background-color: transparent;
                        color: #cdd6f4;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
                        margin: 16px;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    .mermaid {
                        background-color: transparent;
                    }
                </style>
            </head>
            <body>
                <pre class="mermaid">
            \(code)
                </pre>
            </body>
            </html>
            """

        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Adjust height after content loads
            webView.evaluateJavaScript("document.body.scrollHeight") { height, error in
                if let height = height as? CGFloat {
                    DispatchQueue.main.async {
                        webView.frame.size.height = height + 32 // Add padding
                    }
                }
            }
        }
    }
}

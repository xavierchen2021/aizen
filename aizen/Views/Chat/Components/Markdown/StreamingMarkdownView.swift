//  StreamingMarkdownView.swift
//  aizen
//
//  High-performance streaming markdown renderer using NSTextView
//  Supports incremental parsing, cross-block text selection, and SwiftUI overlays
//

import SwiftUI
import AppKit
import Markdown

// MARK: - Streaming Markdown View

struct StreamingMarkdownView: View {
    let content: String
    var isStreaming: Bool = false
    
    @State private var codeBlocks: [CodeBlockInfo] = []
    @State private var textViewHeight: CGFloat = 20
    @State private var containerWidth: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Base text layer with NSTextView
                MarkdownTextView(
                    content: content,
                    isStreaming: isStreaming,
                    codeBlocks: $codeBlocks,
                    contentHeight: $textViewHeight,
                    containerWidth: geo.size.width
                )
                
                // SwiftUI overlay layer for code blocks
                ForEach(codeBlocks) { block in
                    CodeBlockView(
                        code: block.code,
                        language: block.language,
                        isStreaming: isStreaming && block.isLast
                    )
                    .frame(width: max(geo.size.width - 4, 100))
                    .offset(y: block.yOffset)
                }
            }
            .frame(width: geo.size.width)
        }
        .frame(minHeight: textViewHeight)
    }
}

// MARK: - Code Block Info

struct CodeBlockInfo: Identifiable {
    let id: String
    let code: String
    let language: String?
    let yOffset: CGFloat
    let height: CGFloat
    let isLast: Bool
}

// MARK: - Markdown Text View (NSViewRepresentable)

struct MarkdownTextView: NSViewRepresentable {
    let content: String
    var isStreaming: Bool
    @Binding var codeBlocks: [CodeBlockInfo]
    @Binding var contentHeight: CGFloat
    let containerWidth: CGFloat
    
    func makeNSView(context: Context) -> StreamingTextView {
        let textView = StreamingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isRichText = true
        textView.allowsUndo = false
        textView.usesAdaptiveColorMappingForDarkAppearance = true
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        
        textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        
        context.coordinator.textView = textView
        
        return textView
    }
    
    func updateNSView(_ textView: StreamingTextView, context: Context) {
        // Update container width if changed
        if textView.textContainer?.containerSize.width != containerWidth {
            textView.textContainer?.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.maxSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        
        context.coordinator.update(
            content: content,
            isStreaming: isStreaming,
            codeBlocks: $codeBlocks,
            contentHeight: $contentHeight,
            containerWidth: containerWidth
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        weak var textView: StreamingTextView?
        
        private var parser = IncrementalMarkdownParser()
        private var lastContentHash: Int = 0
        private var lastWidth: CGFloat = 0
        private var isUpdating = false
        
        func update(
            content: String,
            isStreaming: Bool,
            codeBlocks: Binding<[CodeBlockInfo]>,
            contentHeight: Binding<CGFloat>,
            containerWidth: CGFloat
        ) {
            guard !isUpdating else { return }
            guard let textView = textView else { return }
            guard containerWidth > 0 else { return }
            
            let contentHash = content.hashValue
            let needsUpdate = contentHash != lastContentHash || containerWidth != lastWidth
            guard needsUpdate else { return }
            
            lastContentHash = contentHash
            lastWidth = containerWidth
            isUpdating = true
            
            defer { isUpdating = false }
            
            // Parse incrementally
            let result = parser.parse(content, isStreaming: isStreaming)
            
            // Build attributed string and collect code block info
            let (attributedString, blocks) = buildAttributedContent(
                from: result,
                isStreaming: isStreaming,
                containerWidth: containerWidth
            )
            
            // Update text storage
            if let textStorage = textView.textStorage {
                textStorage.beginEditing()
                textStorage.setAttributedString(attributedString)
                textStorage.endEditing()
            }
            
            // Force layout
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            
            // Calculate positions for code blocks
            var codeBlockInfos: [CodeBlockInfo] = []
            var currentY: CGFloat = 0
            
            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                let fullRange = NSRange(location: 0, length: attributedString.length)
                layoutManager.ensureLayout(forCharacterRange: fullRange)
                
                // Find code block placeholder positions
                attributedString.enumerateAttribute(.codeBlockMarker, in: fullRange, options: []) { value, range, _ in
                    if let data = value as? CodeBlockMarkerData {
                        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                        
                        let info = CodeBlockInfo(
                            id: "code-\(data.index)",
                            code: data.code,
                            language: data.language,
                            yOffset: rect.minY,
                            height: data.estimatedHeight,
                            isLast: data.isLast
                        )
                        codeBlockInfos.append(info)
                    }
                }
                
                let usedRect = layoutManager.usedRect(for: textContainer)
                currentY = usedRect.height
            }
            
            // Update on main thread
            DispatchQueue.main.async {
                contentHeight.wrappedValue = max(currentY + 8, 20)
                codeBlocks.wrappedValue = codeBlockInfos
            }
        }
        
        private func buildAttributedContent(
            from result: IncrementalMarkdownParser.ParseResult,
            isStreaming: Bool,
            containerWidth: CGFloat
        ) -> (NSMutableAttributedString, [CodeBlockMarkerData]) {
            let output = NSMutableAttributedString()
            var codeBlockMarkers: [CodeBlockMarkerData] = []
            var blockIndex = 0
            
            let defaultFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let defaultColor = NSColor.labelColor
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            
            let blockCount = result.blocks.count
            
            for block in result.blocks {
                let isLastBlock = blockIndex == blockCount - 1
                
                switch block {
                case .paragraph(let text):
                    let para = renderInlineText(text, baseFont: defaultFont, baseColor: defaultColor)
                    let mutable = NSMutableAttributedString(attributedString: para)
                    mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: mutable.length))
                    output.append(mutable)
                    output.append(NSAttributedString(string: "\n\n"))
                    
                case .heading(let text, let level):
                    let font = fontForHeading(level: level)
                    let heading = renderInlineText(text, baseFont: font, baseColor: defaultColor)
                    let mutable = NSMutableAttributedString(attributedString: heading)
                    mutable.addAttribute(.font, value: font, range: NSRange(location: 0, length: mutable.length))
                    output.append(mutable)
                    output.append(NSAttributedString(string: "\n\n"))
                    
                case .codeBlock(let code, let language):
                    // Calculate estimated height for code block
                    let lineCount = code.components(separatedBy: "\n").count
                    let estimatedHeight = CGFloat(lineCount) * 18 + 50 // line height + header + padding
                    
                    // Insert placeholder with proper height using newlines
                    let placeholderLines = max(1, Int(estimatedHeight / 18))
                    let placeholder = String(repeating: "\n", count: placeholderLines)
                    
                    let markerData = CodeBlockMarkerData(
                        code: code,
                        language: language,
                        index: blockIndex,
                        estimatedHeight: estimatedHeight,
                        isLast: isLastBlock
                    )
                    codeBlockMarkers.append(markerData)
                    
                    let placeholderAttr = NSMutableAttributedString(
                        string: placeholder,
                        attributes: [
                            .font: defaultFont,
                            .foregroundColor: NSColor.clear,
                            .codeBlockMarker: markerData
                        ]
                    )
                    output.append(placeholderAttr)
                    output.append(NSAttributedString(string: "\n"))
                    
                case .list(let items, let ordered):
                    for (idx, item) in items.enumerated() {
                        let prefix = ordered ? "\(idx + 1). " : "• "
                        let prefixAttr = NSAttributedString(
                            string: prefix,
                            attributes: [.font: defaultFont, .foregroundColor: defaultColor]
                        )
                        output.append(prefixAttr)
                        let itemText = renderInlineText(item, baseFont: defaultFont, baseColor: defaultColor)
                        output.append(itemText)
                        output.append(NSAttributedString(string: "\n"))
                    }
                    output.append(NSAttributedString(string: "\n"))
                    
                case .blockQuote(let text):
                    let quoteFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    let quoteColor = NSColor.secondaryLabelColor
                    let quoteText = renderInlineText(text, baseFont: quoteFont, baseColor: quoteColor)
                    let mutable = NSMutableAttributedString(string: "┃ ")
                    mutable.addAttributes([.font: quoteFont, .foregroundColor: quoteColor], range: NSRange(location: 0, length: mutable.length))
                    mutable.append(quoteText)
                    output.append(mutable)
                    output.append(NSAttributedString(string: "\n\n"))
                    
                case .image(let url, let alt):
                    let imageText = "📷 \(alt ?? "Image")\n\n"
                    let imageAttr = NSAttributedString(
                        string: imageText,
                        attributes: [
                            .font: defaultFont,
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                    output.append(imageAttr)
                    // TODO: Add image overlay support
                    
                case .mermaidDiagram:
                    let mermaidText = "📊 Mermaid Diagram\n\n"
                    let mermaidAttr = NSAttributedString(
                        string: mermaidText,
                        attributes: [
                            .font: defaultFont,
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                    output.append(mermaidAttr)
                    // TODO: Add mermaid overlay support
                    
                case .table(let header, let rows):
                    let tableText = renderTableAsText(header: header, rows: rows, font: defaultFont)
                    output.append(tableText)
                    output.append(NSAttributedString(string: "\n\n"))
                    
                case .thematicBreak:
                    let hr = NSAttributedString(
                        string: "───────────────────\n\n",
                        attributes: [.font: defaultFont, .foregroundColor: NSColor.separatorColor]
                    )
                    output.append(hr)
                }
                
                blockIndex += 1
            }
            
            // Append streaming buffer if present
            if !result.streamingBuffer.isEmpty {
                let bufferText = NSAttributedString(
                    string: result.streamingBuffer,
                    attributes: [.font: defaultFont, .foregroundColor: defaultColor.withAlphaComponent(0.9)]
                )
                output.append(bufferText)
            }
            
            return (output, codeBlockMarkers)
        }
        
        private func renderInlineText(_ text: String, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
            let parser = InlineMarkdownParser()
            return parser.parse(text, baseFont: baseFont, baseColor: baseColor)
        }
        
        private func fontForHeading(level: Int) -> NSFont {
            switch level {
            case 1: return NSFont.systemFont(ofSize: 28, weight: .bold)
            case 2: return NSFont.systemFont(ofSize: 22, weight: .bold)
            case 3: return NSFont.systemFont(ofSize: 18, weight: .semibold)
            case 4: return NSFont.systemFont(ofSize: 16, weight: .semibold)
            case 5: return NSFont.systemFont(ofSize: 14, weight: .medium)
            default: return NSFont.systemFont(ofSize: 13, weight: .medium)
            }
        }
        
        private func renderTableAsText(header: [String], rows: [[String]], font: NSFont) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let monoFont = NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: NSColor.labelColor]
            
            // Calculate column widths
            var colWidths = header.map { $0.count }
            for row in rows {
                for (i, cell) in row.enumerated() where i < colWidths.count {
                    colWidths[i] = max(colWidths[i], cell.count)
                }
            }
            
            // Header
            var headerLine = "│"
            for (i, cell) in header.enumerated() {
                let padded = cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
                headerLine += " \(padded) │"
            }
            result.append(NSAttributedString(string: headerLine + "\n", attributes: attrs))
            
            // Separator
            var sep = "├"
            for width in colWidths {
                sep += String(repeating: "─", count: width + 2) + "┼"
            }
            sep = String(sep.dropLast()) + "┤"
            result.append(NSAttributedString(string: sep + "\n", attributes: attrs))
            
            // Rows
            for row in rows {
                var rowLine = "│"
                for (i, cell) in row.enumerated() where i < colWidths.count {
                    let padded = cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
                    rowLine += " \(padded) │"
                }
                result.append(NSAttributedString(string: rowLine + "\n", attributes: attrs))
            }
            
            return result
        }
    }
}

// MARK: - Code Block Marker Data

struct CodeBlockMarkerData {
    let code: String
    let language: String?
    let index: Int
    let estimatedHeight: CGFloat
    let isLast: Bool
}

// MARK: - Custom Attributed String Keys

extension NSAttributedString.Key {
    static let codeBlockMarker = NSAttributedString.Key("codeBlockMarker")
}

// MARK: - Streaming Text View

class StreamingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height)
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - Incremental Markdown Parser

class IncrementalMarkdownParser {
    private var completedBlocks: [ParsedBlock] = []
    private var lastStableIndex: Int = 0
    private var lastStableContent: String = ""
    
    struct ParseResult {
        let blocks: [ParsedBlock]
        let streamingBuffer: String
    }
    
    enum ParsedBlock: Equatable {
        case paragraph(String)
        case heading(String, level: Int)
        case codeBlock(String, language: String?)
        case list([String], ordered: Bool)
        case blockQuote(String)
        case image(url: String, alt: String?)
        case mermaidDiagram(String)
        case table(header: [String], rows: [[String]])
        case thematicBreak
    }
    
    func parse(_ content: String, isStreaming: Bool) -> ParseResult {
        if !isStreaming {
            // Full parse for final content
            let blocks = parseAll(content)
            completedBlocks = blocks
            lastStableIndex = content.count
            lastStableContent = content
            return ParseResult(blocks: blocks, streamingBuffer: "")
        }
        
        // Incremental parse for streaming
        let stableBoundary = findStableBoundary(in: content)
        let stableContent = String(content.prefix(stableBoundary))
        
        // Only re-parse if stable content changed
        if stableContent != lastStableContent {
            completedBlocks = parseAll(stableContent)
            lastStableContent = stableContent
            lastStableIndex = stableBoundary
        }
        
        // Buffer is the unstable trailing content
        let buffer = String(content.suffix(content.count - stableBoundary))
        
        return ParseResult(blocks: completedBlocks, streamingBuffer: buffer)
    }
    
    private func findStableBoundary(in content: String) -> Int {
        var inCodeBlock = false
        var lastBoundary = 0
        var i = 0
        let chars = Array(content)
        
        while i < chars.count {
            // Check for code fence
            if i + 2 < chars.count && chars[i] == "`" && chars[i + 1] == "`" && chars[i + 2] == "`" {
                // Find end of line to get full fence
                var endOfLine = i + 3
                while endOfLine < chars.count && chars[endOfLine] != "\n" {
                    endOfLine += 1
                }
                inCodeBlock.toggle()
                i = endOfLine + 1
                
                // If we just closed a code block, mark boundary after the newline
                if !inCodeBlock && i <= chars.count {
                    // Look for double newline after code block
                    if i < chars.count && chars[i] == "\n" {
                        lastBoundary = i + 1
                    }
                }
                continue
            }
            
            // Check for block boundary (double newline) outside code blocks
            if !inCodeBlock && i + 1 < chars.count && chars[i] == "\n" && chars[i + 1] == "\n" {
                lastBoundary = i + 2
            }
            
            i += 1
        }
        
        // If we're in an unclosed code block, boundary is before it started
        if inCodeBlock {
            if let range = content.range(of: "```", options: .backwards) {
                let beforeCodeBlock = content.distance(from: content.startIndex, to: range.lowerBound)
                let prefix = String(content.prefix(beforeCodeBlock))
                if let lastDoubleNewline = prefix.range(of: "\n\n", options: .backwards) {
                    return content.distance(from: content.startIndex, to: lastDoubleNewline.upperBound)
                }
                return 0
            }
        }
        
        return lastBoundary
    }
    
    private func parseAll(_ content: String) -> [ParsedBlock] {
        guard !content.isEmpty else { return [] }
        let document = Document(parsing: content)
        var blocks: [ParsedBlock] = []
        
        for child in document.children {
            if let block = parseBlock(child) {
                blocks.append(block)
            }
        }
        
        return blocks
    }
    
    private func parseBlock(_ markup: Markup) -> ParsedBlock? {
        if let paragraph = markup as? Paragraph {
            // Check for image-only paragraph
            if let image = paragraph.children.first as? Markdown.Image, paragraph.childCount == 1 {
                return .image(url: image.source ?? "", alt: extractPlainText(from: image))
            }
            
            let text = extractPlainText(from: paragraph)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .paragraph(text)
        }
        
        if let heading = markup as? Heading {
            return .heading(extractPlainText(from: heading), level: heading.level)
        }
        
        if let codeBlock = markup as? CodeBlock {
            if codeBlock.language?.lowercased() == "mermaid" {
                return .mermaidDiagram(codeBlock.code)
            }
            return .codeBlock(codeBlock.code, language: codeBlock.language)
        }
        
        if let list = markup as? UnorderedList {
            let items = list.listItems.map { self.extractPlainText(from: $0) }
            return .list(Array(items), ordered: false)
        }
        
        if let list = markup as? OrderedList {
            let items = list.listItems.map { self.extractPlainText(from: $0) }
            return .list(Array(items), ordered: true)
        }
        
        if let quote = markup as? BlockQuote {
            return .blockQuote(self.extractPlainText(from: quote))
        }
        
        if let table = markup as? Markdown.Table {
            let header = table.head.cells.map { self.extractPlainText(from: $0) }
            let rows = table.body.rows.map { row in
                Array(row.cells.map { self.extractPlainText(from: $0) })
            }
            return .table(header: Array(header), rows: Array(rows))
        }
        
        if markup is ThematicBreak {
            return .thematicBreak
        }
        
        return nil
    }
    
    private func extractPlainText(from markup: Markup) -> String {
        var result = ""
        for child in markup.children {
            if let text = child as? Markdown.Text {
                result += text.string
            } else if let code = child as? InlineCode {
                result += "`\(code.code)`"
            } else if let strong = child as? Strong {
                result += "**\(extractPlainText(from: strong))**"
            } else if let emphasis = child as? Emphasis {
                result += "*\(extractPlainText(from: emphasis))*"
            } else if let link = child as? Markdown.Link {
                result += "[\(extractPlainText(from: link))](\(link.destination ?? ""))"
            } else if child is SoftBreak {
                result += " "
            } else if child is LineBreak {
                result += "\n"
            } else {
                result += extractPlainText(from: child)
            }
        }
        return result
    }
    
    func reset() {
        completedBlocks = []
        lastStableIndex = 0
        lastStableContent = ""
    }
}

// MARK: - Inline Markdown Parser

class InlineMarkdownParser {
    func parse(_ text: String, baseFont: NSFont, baseColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var current = text.startIndex
        let end = text.endIndex
        
        while current < end {
            // Check for inline code
            if text[current] == "`" {
                if let (code, newIndex) = parseInlineCode(text, from: current) {
                    let codeFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                    let codeAttr = NSAttributedString(
                        string: code,
                        attributes: [
                            .font: codeFont,
                            .foregroundColor: baseColor,
                            .backgroundColor: NSColor.quaternaryLabelColor
                        ]
                    )
                    result.append(codeAttr)
                    current = newIndex
                    continue
                }
            }
            
            // Check for bold (**text**)
            if text[current] == "*",
               text.index(after: current) < end,
               text[text.index(after: current)] == "*" {
                if let (boldText, newIndex) = parseBold(text, from: current) {
                    let boldFont = NSFont.systemFont(ofSize: baseFont.pointSize, weight: .bold)
                    let boldAttr = NSAttributedString(
                        string: boldText,
                        attributes: [.font: boldFont, .foregroundColor: baseColor]
                    )
                    result.append(boldAttr)
                    current = newIndex
                    continue
                }
            }
            
            // Check for italic (*text*)
            if text[current] == "*" {
                if let (italicText, newIndex) = parseItalic(text, from: current) {
                    let italicFont = NSFont.systemFont(ofSize: baseFont.pointSize).italic()
                    let italicAttr = NSAttributedString(
                        string: italicText,
                        attributes: [.font: italicFont, .foregroundColor: baseColor]
                    )
                    result.append(italicAttr)
                    current = newIndex
                    continue
                }
            }
            
            // Check for links [text](url)
            if text[current] == "[" {
                if let (linkText, url, newIndex) = parseLink(text, from: current) {
                    var linkAttrs: [NSAttributedString.Key: Any] = [
                        .font: baseFont,
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ]
                    if let linkURL = URL(string: url) {
                        linkAttrs[.link] = linkURL
                    }
                    let linkAttr = NSAttributedString(string: linkText, attributes: linkAttrs)
                    result.append(linkAttr)
                    current = newIndex
                    continue
                }
            }
            
            // Regular character
            let char = NSAttributedString(
                string: String(text[current]),
                attributes: [.font: baseFont, .foregroundColor: baseColor]
            )
            result.append(char)
            current = text.index(after: current)
        }
        
        return result
    }
    
    private func parseInlineCode(_ text: String, from start: String.Index) -> (String, String.Index)? {
        guard text[start] == "`" else { return nil }
        var current = text.index(after: start)
        var code = ""
        
        while current < text.endIndex {
            if text[current] == "`" {
                return (code, text.index(after: current))
            }
            code.append(text[current])
            current = text.index(after: current)
        }
        return nil
    }
    
    private func parseBold(_ text: String, from start: String.Index) -> (String, String.Index)? {
        guard text[start] == "*",
              text.index(after: start) < text.endIndex,
              text[text.index(after: start)] == "*" else { return nil }
        
        var current = text.index(start, offsetBy: 2)
        var content = ""
        
        while current < text.endIndex {
            if text[current] == "*",
               text.index(after: current) < text.endIndex,
               text[text.index(after: current)] == "*" {
                return (content, text.index(current, offsetBy: 2))
            }
            content.append(text[current])
            current = text.index(after: current)
        }
        return nil
    }
    
    private func parseItalic(_ text: String, from start: String.Index) -> (String, String.Index)? {
        guard text[start] == "*" else { return nil }
        // Make sure it's not bold
        if text.index(after: start) < text.endIndex && text[text.index(after: start)] == "*" {
            return nil
        }
        
        var current = text.index(after: start)
        var content = ""
        
        while current < text.endIndex {
            if text[current] == "*" {
                return (content, text.index(after: current))
            }
            content.append(text[current])
            current = text.index(after: current)
        }
        return nil
    }
    
    private func parseLink(_ text: String, from start: String.Index) -> (String, String, String.Index)? {
        guard text[start] == "[" else { return nil }
        
        var current = text.index(after: start)
        var linkText = ""
        
        // Find ]
        while current < text.endIndex && text[current] != "]" {
            linkText.append(text[current])
            current = text.index(after: current)
        }
        
        guard current < text.endIndex, text[current] == "]" else { return nil }
        current = text.index(after: current)
        
        // Expect (
        guard current < text.endIndex, text[current] == "(" else { return nil }
        current = text.index(after: current)
        
        // Find )
        var url = ""
        while current < text.endIndex && text[current] != ")" {
            url.append(text[current])
            current = text.index(after: current)
        }
        
        guard current < text.endIndex, text[current] == ")" else { return nil }
        return (linkText, url, text.index(after: current))
    }
}

// MARK: - NSFont Extension

extension NSFont {
    func italic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}

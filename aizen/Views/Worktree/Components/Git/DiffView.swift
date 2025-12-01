//
//  DiffView.swift
//  aizen
//
//  NSTableView-based diff renderer for git changes
//

import SwiftUI
import AppKit

struct DiffView: NSViewRepresentable {
    // Input mode 1: Raw diff string (for multi-file view)
    private let diffOutput: String?

    // Input mode 2: Pre-parsed lines (for single-file view)
    private let preloadedLines: [DiffLine]?

    let fontSize: Double
    let fontFamily: String
    let repoPath: String
    let showFileHeaders: Bool
    let scrollToFile: String?
    let onFileVisible: ((String) -> Void)?
    let onOpenFile: ((String) -> Void)?

    // Init for raw diff output (used by GitChangesOverlayView)
    init(
        diffOutput: String,
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        scrollToFile: String? = nil,
        onFileVisible: ((String) -> Void)? = nil,
        onOpenFile: ((String) -> Void)? = nil
    ) {
        self.diffOutput = diffOutput
        self.preloadedLines = nil
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = true
        self.scrollToFile = scrollToFile
        self.onFileVisible = onFileVisible
        self.onOpenFile = onOpenFile
    }

    // Init for pre-parsed lines (used by FileDiffSectionView)
    init(
        lines: [DiffLine],
        fontSize: Double,
        fontFamily: String,
        repoPath: String = "",
        showFileHeaders: Bool = false
    ) {
        self.diffOutput = nil
        self.preloadedLines = lines
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.repoPath = repoPath
        self.showFileHeaders = showFileHeaders
        self.scrollToFile = nil
        self.onFileVisible = nil
        self.onOpenFile = nil
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        tableView.style = .plain
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.rowSizeStyle = .custom
        tableView.gridStyleMask = []
        tableView.gridColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .clear
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders
        context.coordinator.setupScrollObserver(for: scrollView)

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onFileVisible = onFileVisible
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.repoPath = repoPath
        context.coordinator.showFileHeaders = showFileHeaders

        if let lines = preloadedLines {
            context.coordinator.loadLines(lines, fontSize: fontSize, fontFamily: fontFamily)
        } else if let output = diffOutput {
            context.coordinator.parseAndReload(diffOutput: output, fontSize: fontSize, fontFamily: fontFamily)
        }

        // Handle scroll to file request
        if let file = scrollToFile, file != context.coordinator.lastScrolledFile {
            context.coordinator.scrollToFile(file)
            context.coordinator.lastScrolledFile = file
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(repoPath: repoPath, showFileHeaders: showFileHeaders, onOpenFile: onOpenFile)
    }

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: NSTableView?
        var rows: [DiffRow] = []
        var rowHeight: CGFloat = 20
        var fontSize: Double = 12
        var fontFamily: String = "Menlo"
        var repoPath: String = ""
        var showFileHeaders: Bool = true
        var onFileVisible: ((String) -> Void)?
        var onOpenFile: ((String) -> Void)?
        var lastScrolledFile: String?
        private var lastDataHash: Int = 0
        private var fileRowIndices: [String: Int] = [:]  // Map file path to row index
        private var lastVisibleFile: String?
        private var scrollObserver: NSObjectProtocol?

        init(repoPath: String, showFileHeaders: Bool, onOpenFile: ((String) -> Void)?) {
            self.repoPath = repoPath
            self.showFileHeaders = showFileHeaders
            self.onOpenFile = onOpenFile
            super.init()
        }

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        enum DiffRow {
            case fileHeader(path: String)
            case line(DiffLine)
            case lazyLine(rawIndex: Int)
        }

        func setupScrollObserver(for scrollView: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.updateVisibleFile()
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        private func updateVisibleFile() {
            guard let tableView = tableView else { return }
            let visibleRect = tableView.visibleRect

            // Find the file header that best represents what's currently visible
            var currentFile: String?
            var lastFileBeforeVisible: String?

            for (index, row) in rows.enumerated() {
                if case .fileHeader(let path) = row {
                    let rowRect = tableView.rect(ofRow: index)

                    // If this header is above the visible area, remember it
                    if rowRect.maxY <= visibleRect.minY + 20 {
                        lastFileBeforeVisible = path
                    }
                    // If this header is within the visible area
                    else if rowRect.minY < visibleRect.maxY {
                        // If header is at or near the top of visible area, this is our file
                        if rowRect.minY <= visibleRect.minY + 50 {
                            currentFile = path
                        } else if currentFile == nil {
                            // First header we see in the visible area
                            currentFile = path
                        }
                    }
                }
            }

            // If no header is visible but we scrolled past one, use that
            if currentFile == nil {
                currentFile = lastFileBeforeVisible
            }

            if let file = currentFile, file != lastVisibleFile {
                lastVisibleFile = file
                onFileVisible?(file)
            }
        }

        func scrollToFile(_ file: String) {
            guard let tableView = tableView,
                  let rowIndex = fileRowIndices[file] else { return }

            tableView.scrollRowToVisible(rowIndex)
            // Scroll a bit more to show the header at the top
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                let rowRect = tableView.rect(ofRow: rowIndex)
                tableView.enclosingScrollView?.contentView.scroll(to: NSPoint(x: 0, y: rowRect.minY))
            }
        }

        // Load pre-parsed DiffLine array
        func loadLines(_ lines: [DiffLine], fontSize: Double, fontFamily: String) {
            let newHash = lines.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            rows = lines.map { .line($0) }
            tableView?.reloadData()
        }

        // Parse raw diff output - store raw lines for lazy parsing
        func parseAndReload(diffOutput: String, fontSize: Double, fontFamily: String) {
            let newHash = diffOutput.hashValue ^ fontSize.hashValue ^ fontFamily.hashValue
            guard newHash != lastDataHash else { return }

            lastDataHash = newHash
            self.fontSize = fontSize
            self.fontFamily = fontFamily

            let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            rowHeight = ceil(font.ascender - font.descender + font.leading) + 6

            // Store raw lines for lazy parsing
            rawLines = []
            rawLines.reserveCapacity(diffOutput.count / 40)
            diffOutput.enumerateLines { [self] line, _ in
                rawLines.append(line)
            }

            // Clear parsed cache
            parsedRows.removeAll(keepingCapacity: true)
            fileRowIndices.removeAll()
            rows.removeAll(keepingCapacity: true)

            // Build row metadata quickly (just count and identify file headers)
            buildRowMetadata()

            tableView?.reloadData()
        }

        private var rawLines: [String] = []
        private var parsedRows: [Int: DiffRow] = [:] // Lazy cache

        private func buildRowMetadata() {
            var rowIndex = 0
            var oldNum = 0
            var newNum = 0

            for (lineIndex, line) in rawLines.enumerated() {
                let firstChar = line.first

                if line.hasPrefix("diff --git ") {
                    continue
                } else if line.hasPrefix("+++ b/") {
                    let path = String(line.dropFirst(6))
                    if showFileHeaders {
                        fileRowIndices[path] = rowIndex
                        rows.append(.fileHeader(path: path))
                        rowIndex += 1
                    }
                } else if firstChar == "-" && line.hasPrefix("--- ") {
                    continue
                } else if line.hasPrefix("index ") || line.hasPrefix("new file") || line.hasPrefix("deleted file") {
                    continue
                } else if firstChar == "@" || firstChar == "+" || firstChar == "-" || firstChar == " " {
                    // Just add placeholder - will parse on demand
                    rows.append(.lazyLine(rawIndex: lineIndex))
                    rowIndex += 1
                }
            }
        }

        // Parse a single line on demand
        private func parseLineAt(_ rawIndex: Int) -> DiffLine {
            let line = rawLines[rawIndex]
            let firstChar = line.first

            // Need to calculate line numbers by scanning backwards
            var oldNum = 0
            var newNum = 0

            // Find the most recent @@ header to get starting line numbers
            for i in stride(from: rawIndex - 1, through: 0, by: -1) {
                let prevLine = rawLines[i]
                if prevLine.hasPrefix("@@") {
                    // Parse hunk header
                    if let minusRange = prevLine.range(of: "-") {
                        let afterMinus = prevLine[minusRange.upperBound...]
                        if let end = afterMinus.firstIndex(where: { $0 == "," || $0 == " " }),
                           let num = Int(afterMinus[..<end]) {
                            oldNum = num
                        }
                    }
                    if let plusRange = prevLine.range(of: " +") {
                        let afterPlus = prevLine[plusRange.upperBound...]
                        if let end = afterPlus.firstIndex(where: { $0 == "," || $0 == " " }),
                           let num = Int(afterPlus[..<end]) {
                            newNum = num
                        }
                    }
                    // Count lines between header and current
                    for j in (i + 1)..<rawIndex {
                        let scanLine = rawLines[j]
                        let scanChar = scanLine.first
                        if scanChar == "+" { newNum += 1 }
                        else if scanChar == "-" { oldNum += 1 }
                        else if scanChar == " " { oldNum += 1; newNum += 1 }
                    }
                    break
                }
            }

            if firstChar == "@" {
                return DiffLine(lineNumber: rawIndex, oldLineNumber: nil, newLineNumber: nil, content: line, type: .header)
            } else if firstChar == "+" {
                return DiffLine(lineNumber: rawIndex, oldLineNumber: nil, newLineNumber: String(newNum + 1), content: String(line.dropFirst()), type: .added)
            } else if firstChar == "-" {
                return DiffLine(lineNumber: rawIndex, oldLineNumber: String(oldNum + 1), newLineNumber: nil, content: String(line.dropFirst()), type: .deleted)
            } else {
                return DiffLine(lineNumber: rawIndex, oldLineNumber: String(oldNum + 1), newLineNumber: String(newNum + 1), content: String(line.dropFirst()), type: .context)
            }
        }

        func getRow(at index: Int) -> DiffRow {
            guard index < rows.count else { return .line(DiffLine(lineNumber: 0, oldLineNumber: nil, newLineNumber: nil, content: "", type: .context)) }

            switch rows[index] {
            case .lazyLine(let rawIndex):
                // Parse on demand and cache
                if let cached = parsedRows[index] {
                    return cached
                }
                let parsed = DiffRow.line(parseLineAt(rawIndex))
                parsedRows[index] = parsed
                return parsed
            default:
                return rows[index]
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < rows.count else { return rowHeight }
            switch rows[row] {
            case .fileHeader:
                return rowHeight + 12
            case .line, .lazyLine:
                return rowHeight
            }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count else { return nil }

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader(let path):
                return makeFileHeaderCell(path: path, tableView: tableView)
            case .line(let diffLine):
                return makeLineCell(diffLine: diffLine, tableView: tableView)
            case .lazyLine:
                return nil // Should never happen after getRow
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard row < rows.count else { return nil }
            let rowView = DiffNSRowView()

            let resolvedRow = getRow(at: row)
            switch resolvedRow {
            case .fileHeader:
                rowView.lineType = nil
            case .line(let diffLine):
                rowView.lineType = diffLine.type
            case .lazyLine:
                rowView.lineType = .context
            }

            return rowView
        }

        private func makeFileHeaderCell(path: String, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("FileHeader")
            if let cell = tableView.makeView(withIdentifier: id, owner: nil) as? FileHeaderCellView {
                cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
                return cell
            }
            let cell = FileHeaderCellView(identifier: id)
            cell.configure(path: path, repoPath: repoPath, fontSize: fontSize, fontFamily: fontFamily, onOpenFile: onOpenFile)
            return cell
        }

        private func makeLineCell(diffLine: DiffLine, tableView: NSTableView) -> NSView {
            let id = NSUserInterfaceItemIdentifier("DiffLine")
            if let cell = tableView.makeView(withIdentifier: id, owner: nil) as? LineCellView {
                cell.configure(diffLine: diffLine, fontSize: fontSize, fontFamily: fontFamily)
                return cell
            }
            let cell = LineCellView(identifier: id)
            cell.configure(diffLine: diffLine, fontSize: fontSize, fontFamily: fontFamily)
            return cell
        }
    }
}

// MARK: - Row View

private class DiffNSRowView: NSTableRowView {
    var lineType: DiffLineType? {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let type = lineType else {
            // File header
            NSColor.controlBackgroundColor.withAlphaComponent(0.8).setFill()
            bounds.fill()
            return
        }
        type.nsBackgroundColor.setFill()
        bounds.fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

// MARK: - File Header Cell

private class FileHeaderCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let openButton = NSButton()
    private var currentPath: String = ""
    private var onOpenFile: ((String) -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 1

        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.bezelStyle = .accessoryBarAction
        openButton.isBordered = false
        openButton.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Open in editor")
        openButton.contentTintColor = .secondaryLabelColor
        openButton.target = self
        openButton.action = #selector(openFile)
        openButton.toolTip = "Open in editor"

        addSubview(iconView)
        addSubview(pathLabel)
        addSubview(openButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            pathLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            openButton.leadingAnchor.constraint(greaterThanOrEqualTo: pathLabel.trailingAnchor, constant: 8),
            openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            openButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 20),
            openButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    @objc private func openFile() {
        onOpenFile?(currentPath)
    }

    func configure(path: String, repoPath: String, fontSize: Double, fontFamily: String, onOpenFile: ((String) -> Void)?) {
        currentPath = path
        self.onOpenFile = onOpenFile

        pathLabel.stringValue = path
        pathLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

        let fullPath = (repoPath as NSString).appendingPathComponent(path)
        Task { @MainActor in
            if let icon = await FileIconService.shared.icon(forFile: fullPath, size: CGSize(width: 16, height: 16)) {
                self.iconView.image = icon
            } else {
                self.iconView.image = NSWorkspace.shared.icon(forFileType: (path as NSString).pathExtension)
            }
        }
    }
}

// MARK: - Line Cell

private class LineCellView: NSTableCellView {
    private let oldNumLabel = NSTextField(labelWithString: "")
    private let newNumLabel = NSTextField(labelWithString: "")
    private let markerLabel = NSTextField(labelWithString: "")
    private let contentLabel = NSTextField(labelWithString: "")
    private let lineNumBg = NSView()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        lineNumBg.wantsLayer = true
        lineNumBg.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        lineNumBg.translatesAutoresizingMaskIntoConstraints = false

        [oldNumLabel, newNumLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.alignment = .right
            $0.textColor = .tertiaryLabelColor
        }

        markerLabel.translatesAutoresizingMaskIntoConstraints = false
        markerLabel.alignment = .center

        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.lineBreakMode = .byClipping
        contentLabel.maximumNumberOfLines = 1
        contentLabel.isSelectable = true

        addSubview(lineNumBg)
        addSubview(oldNumLabel)
        addSubview(newNumLabel)
        addSubview(markerLabel)
        addSubview(contentLabel)

        NSLayoutConstraint.activate([
            lineNumBg.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumBg.topAnchor.constraint(equalTo: topAnchor),
            lineNumBg.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumBg.widthAnchor.constraint(equalToConstant: 56),

            oldNumLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            oldNumLabel.widthAnchor.constraint(equalToConstant: 22),
            oldNumLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            newNumLabel.leadingAnchor.constraint(equalTo: oldNumLabel.trailingAnchor, constant: 4),
            newNumLabel.widthAnchor.constraint(equalToConstant: 22),
            newNumLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            markerLabel.leadingAnchor.constraint(equalTo: lineNumBg.trailingAnchor, constant: 4),
            markerLabel.widthAnchor.constraint(equalToConstant: 16),
            markerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            contentLabel.leadingAnchor.constraint(equalTo: markerLabel.trailingAnchor, constant: 4),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            contentLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(diffLine: DiffLine, fontSize: Double, fontFamily: String) {
        let font = NSFont(name: fontFamily, size: fontSize) ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let smallFont = NSFont(name: fontFamily, size: fontSize - 1) ?? NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)

        oldNumLabel.stringValue = diffLine.oldLineNumber ?? ""
        oldNumLabel.font = smallFont
        oldNumLabel.alphaValue = diffLine.oldLineNumber != nil ? 1 : 0

        newNumLabel.stringValue = diffLine.newLineNumber ?? ""
        newNumLabel.font = smallFont
        newNumLabel.alphaValue = diffLine.newLineNumber != nil ? 1 : 0

        markerLabel.stringValue = diffLine.type.marker
        markerLabel.font = font
        markerLabel.textColor = diffLine.type.nsMarkerColor

        contentLabel.stringValue = diffLine.content.isEmpty ? " " : diffLine.content
        contentLabel.font = font
    }
}

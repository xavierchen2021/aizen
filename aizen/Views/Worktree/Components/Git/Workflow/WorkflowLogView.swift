//
//  WorkflowLogView.swift
//  aizen
//
//  NSTableView-based log viewer for workflow logs with collapsible groups
//

import SwiftUI
import AppKit

// MARK: - Custom Table View with Copy Support

class LogTableView: NSTableView {
    weak var coordinator: WorkflowLogTableView.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            copy(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let coordinator = coordinator else { return }
        let selectedContent = coordinator.getSelectedContent()
        guard !selectedContent.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedContent, forType: .string)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return selectedRowIndexes.count > 0
        }
        return super.validateUserInterfaceItem(item)
    }
}

// MARK: - NSViewRepresentable Log Table

struct WorkflowLogTableView: NSViewRepresentable {
    let logs: String
    let fontSize: CGFloat
    @Binding var showTimestamps: Bool
    var onCoordinatorReady: ((Coordinator) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        onCoordinatorReady?(context.coordinator)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let tableView = LogTableView()
        tableView.coordinator = context.coordinator
        context.coordinator.tableView = tableView

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LogColumn"))
        column.width = 10000
        column.minWidth = 100
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = NSColor.textBackgroundColor
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.style = .plain
        tableView.gridStyleMask = []

        scrollView.documentView = tableView

        // Parse logs in background
        context.coordinator.parseLogs(logs, fontSize: fontSize, showTimestamps: showTimestamps)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if context.coordinator.currentLogs != logs {
            context.coordinator.parseLogs(logs, fontSize: fontSize, showTimestamps: showTimestamps)
        }
        if context.coordinator.showTimestamps != showTimestamps {
            context.coordinator.showTimestamps = showTimestamps
            context.coordinator.tableView?.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        weak var tableView: LogTableView?
        var steps: [LogStep] = []
        var displayRows: [LogRow] = []
        var currentLogs: String = ""
        var fontSize: CGFloat = 11
        var showTimestamps: Bool = false

        private var parseTask: Task<Void, Never>?

        func parseLogs(_ logs: String, fontSize: CGFloat, showTimestamps: Bool) {
            currentLogs = logs
            self.fontSize = fontSize
            self.showTimestamps = showTimestamps

            parseTask?.cancel()
            parseTask = Task.detached(priority: .userInitiated) { [weak self] in
                let parsed = Self.parseLogSteps(logs, fontSize: fontSize)

                await MainActor.run {
                    guard let self = self else { return }
                    self.steps = parsed
                    self.rebuildDisplayRows()
                    self.tableView?.reloadData()
                }
            }
        }

        private static func parseLogSteps(_ text: String, fontSize: CGFloat) -> [LogStep] {
            let lines = text.components(separatedBy: "\n")
            var steps: [LogStep] = []
            var stepNameCounts: [String: Int] = [:] // track occurrences of each step name
            var currentStepName = "" // raw step name from current line
            var currentGroup: LogGroup?
            var groupId = 0
            var lineId = 0
            var stepId = 0
            var currentStyle = ANSITextStyle()
            var lastGroupTitle = ""

            for line in lines {
                // Extract step name from log line format
                let (extractedStep, message) = extractStepAndMessage(line)

                // Handle step transitions
                if !extractedStep.isEmpty && extractedStep != currentStepName {
                    // Save current group to previous step before transitioning
                    if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                        steps[steps.count - 1].groups.append(group)
                        currentGroup = nil
                    }

                    currentStepName = extractedStep

                    // Always create a new step when the name changes
                    let count = stepNameCounts[extractedStep, default: 0]
                    stepNameCounts[extractedStep] = count + 1

                    let displayName = count > 0 ? "\(extractedStep) (\(count + 1))" : extractedStep
                    steps.append(LogStep(id: stepId, name: displayName, groups: [], isExpanded: false))
                    stepId += 1
                }

                // Helper to get current step index
                let currentStepIdx = steps.isEmpty ? nil : steps.count - 1

                // Check for group markers
                if message.contains("##[group]") {
                    // Save current group
                    if let group = currentGroup, !group.lines.isEmpty, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                    }

                    // Extract group title
                    var title = "Output"
                    if let range = message.range(of: "##[group]") {
                        title = String(message[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if title.isEmpty { title = "Output" }
                    }

                    // If this is "Output", merge with previous group instead of creating new one
                    if title == "Output" && !lastGroupTitle.isEmpty {
                        // Continue using the previous group - don't create new one
                        if let stepIdx = currentStepIdx, !steps[stepIdx].groups.isEmpty {
                            let lastIdx = steps[stepIdx].groups.count - 1
                            currentGroup = steps[stepIdx].groups[lastIdx]
                            steps[stepIdx].groups.removeLast()
                        } else {
                            currentGroup = LogGroup(id: groupId, title: lastGroupTitle, lines: [], isExpanded: false)
                            groupId += 1
                        }
                    } else {
                        currentGroup = LogGroup(id: groupId, title: title, lines: [], isExpanded: false)
                        lastGroupTitle = title
                        groupId += 1
                    }
                } else if message.contains("##[endgroup]") {
                    // End current group
                    if let group = currentGroup, let stepIdx = currentStepIdx {
                        steps[stepIdx].groups.append(group)
                        currentGroup = nil
                    }
                } else if !message.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Regular log line - add to current group
                    let (attributed, newStyle) = parseLineToAttributedString(message, style: currentStyle, fontSize: fontSize)
                    currentStyle = newStyle

                    if currentGroup != nil {
                        currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                    } else if let stepIdx = currentStepIdx {
                        // Line outside group - create implicit group for ungrouped content
                        if steps[stepIdx].groups.isEmpty || !steps[stepIdx].groups.last!.title.isEmpty {
                            currentGroup = LogGroup(id: groupId, title: "", lines: [], isExpanded: true)
                            groupId += 1
                        } else {
                            currentGroup = steps[stepIdx].groups.removeLast()
                        }
                        currentGroup?.lines.append((id: lineId, raw: message, attributed: attributed))
                    }
                    lineId += 1
                }
            }

            // Save final group
            if let group = currentGroup, !group.lines.isEmpty, !steps.isEmpty {
                steps[steps.count - 1].groups.append(group)
            }

            // Filter out empty steps
            return steps.filter { !$0.groups.isEmpty || $0.groups.contains { !$0.lines.isEmpty } }
        }

        private static func extractStepAndMessage(_ line: String) -> (step: String, message: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // GitHub Actions format: "job-name    step-name    timestamp message"
            // Match timestamp pattern
            let timestampPattern = #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)"#
            guard let regex = try? NSRegularExpression(pattern: timestampPattern, options: []) else {
                return ("", trimmed)
            }

            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
                  let timestampRange = Range(match.range, in: trimmed) else {
                return ("", trimmed)
            }

            let beforeTimestamp = String(trimmed[..<timestampRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let afterTimestamp = String(trimmed[timestampRange.upperBound...]).trimmingCharacters(in: .whitespaces)

            // Parse job and step from beforeTimestamp
            // Split by multiple whitespace
            let parts = beforeTimestamp.split(omittingEmptySubsequences: true) { $0.isWhitespace }

            var stepName = ""
            if parts.count >= 2 {
                // Step name is everything after job name
                stepName = parts[1..<parts.count].joined(separator: " ")
            }

            return (stepName, afterTimestamp)
        }

        private static func parseLineToAttributedString(_ text: String, style: ANSITextStyle, fontSize: CGFloat) -> (NSAttributedString, ANSITextStyle) {
            let result = NSMutableAttributedString()
            var currentStyle = style

            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]

            let pattern = "\u{001B}\\[([0-9;]*)m"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                return (NSAttributedString(string: text, attributes: defaultAttrs), currentStyle)
            }

            var lastEnd = text.startIndex
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let textBefore = String(text[lastEnd..<swiftRange.lowerBound])
                    if !textBefore.isEmpty {
                        result.append(NSAttributedString(string: textBefore, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
                    }

                    if let codeRange = Range(match.range(at: 1), in: text) {
                        let codes = String(text[codeRange])
                        parseANSICodes(codes, style: &currentStyle)
                    }

                    lastEnd = swiftRange.upperBound
                }
            }

            let remaining = String(text[lastEnd...])
            if !remaining.isEmpty {
                result.append(NSAttributedString(string: remaining, attributes: attributesForStyle(currentStyle, fontSize: fontSize)))
            }

            if result.length == 0 {
                result.append(NSAttributedString(string: " ", attributes: defaultAttrs))
            }

            return (result, currentStyle)
        }

        private static func attributesForStyle(_ style: ANSITextStyle, fontSize: CGFloat) -> [NSAttributedString.Key: Any] {
            var attrs: [NSAttributedString.Key: Any] = [:]

            let weight: NSFont.Weight = style.bold ? .bold : .regular
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)

            var color = NSColor.labelColor
            switch style.foreground {
            case .red: color = NSColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1)
            case .green: color = NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1)
            case .yellow: color = NSColor(red: 0.8, green: 0.8, blue: 0.2, alpha: 1)
            case .blue: color = NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            case .magenta: color = NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1)
            case .cyan: color = NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
            case .brightRed: color = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
            case .brightGreen: color = NSColor(red: 0.4, green: 1.0, blue: 0.4, alpha: 1)
            case .brightYellow: color = NSColor(red: 1.0, green: 1.0, blue: 0.4, alpha: 1)
            case .brightBlue: color = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1)
            case .brightMagenta: color = NSColor(red: 1.0, green: 0.4, blue: 1.0, alpha: 1)
            case .brightCyan: color = NSColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1)
            case .white, .brightWhite: color = NSColor.white
            case .black, .brightBlack: color = NSColor(white: 0.4, alpha: 1)
            default: break
            }

            if style.dim {
                color = color.withAlphaComponent(0.6)
            }
            attrs[.foregroundColor] = color

            if style.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            return attrs
        }

        private static func parseANSICodes(_ codes: String, style: inout ANSITextStyle) {
            let parts = codes.split(separator: ";").compactMap { Int($0) }
            if parts.isEmpty { style.reset(); return }

            for code in parts {
                switch code {
                case 0: style.reset()
                case 1: style.bold = true
                case 2: style.dim = true
                case 4: style.underline = true
                case 22: style.bold = false; style.dim = false
                case 24: style.underline = false
                case 30: style.foreground = .black
                case 31: style.foreground = .red
                case 32: style.foreground = .green
                case 33: style.foreground = .yellow
                case 34: style.foreground = .blue
                case 35: style.foreground = .magenta
                case 36: style.foreground = .cyan
                case 37: style.foreground = .white
                case 39: style.foreground = .default
                case 90: style.foreground = .brightBlack
                case 91: style.foreground = .brightRed
                case 92: style.foreground = .brightGreen
                case 93: style.foreground = .brightYellow
                case 94: style.foreground = .brightBlue
                case 95: style.foreground = .brightMagenta
                case 96: style.foreground = .brightCyan
                case 97: style.foreground = .brightWhite
                default: break
                }
            }
        }

        func rebuildDisplayRows() {
            displayRows.removeAll()
            for step in steps {
                // Count total lines in step
                let totalLines = step.groups.reduce(0) { $0 + $1.lines.count }

                // Add step header
                displayRows.append(.stepHeader(id: step.id, name: step.name, groupCount: totalLines, isExpanded: step.isExpanded))

                // Add groups and lines if step is expanded
                if step.isExpanded {
                    for group in step.groups {
                        // Add group header (only if it has a title)
                        if !group.title.isEmpty {
                            displayRows.append(.groupHeader(id: group.id, stepId: step.id, title: group.title, lineCount: group.lines.count, isExpanded: group.isExpanded))
                        }

                        // Add lines if expanded or if no header (ungrouped)
                        if group.isExpanded || group.title.isEmpty {
                            for line in group.lines {
                                displayRows.append(.logLine(id: line.id, content: line.raw, attributedContent: line.attributed))
                            }
                        }
                    }
                }
            }
        }

        func toggleStep(_ stepId: Int) {
            if let index = steps.firstIndex(where: { $0.id == stepId }) {
                steps[index].isExpanded.toggle()
                rebuildDisplayRows()
                tableView?.reloadData()
            }
        }

        func toggleGroup(_ groupId: Int, inStep stepId: Int) {
            if let stepIndex = steps.firstIndex(where: { $0.id == stepId }),
               let groupIndex = steps[stepIndex].groups.firstIndex(where: { $0.id == groupId }) {
                steps[stepIndex].groups[groupIndex].isExpanded.toggle()
                rebuildDisplayRows()
                tableView?.reloadData()
            }
        }

        func expandAll() {
            for i in steps.indices {
                steps[i].isExpanded = true
                for j in steps[i].groups.indices {
                    steps[i].groups[j].isExpanded = true
                }
            }
            rebuildDisplayRows()
            tableView?.reloadData()
        }

        func collapseAll() {
            for i in steps.indices {
                steps[i].isExpanded = false
                for j in steps[i].groups.indices {
                    steps[i].groups[j].isExpanded = false
                }
            }
            rebuildDisplayRows()
            tableView?.reloadData()
        }

        func copyAllLogs() {
            var allLines: [String] = []
            for step in steps {
                for group in step.groups {
                    for line in group.lines {
                        allLines.append(line.raw)
                    }
                }
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(allLines.joined(separator: "\n"), forType: .string)
        }

        func copyStepLogs(_ stepId: Int) {
            guard let step = steps.first(where: { $0.id == stepId }) else { return }
            var lines: [String] = []
            for group in step.groups {
                for line in group.lines {
                    lines.append(line.raw)
                }
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        }

        func getSelectedContent() -> String {
            guard let tableView = tableView else { return "" }
            var lines: [String] = []
            for rowIndex in tableView.selectedRowIndexes {
                guard rowIndex < displayRows.count else { continue }
                switch displayRows[rowIndex] {
                case .logLine(_, let content, _):
                    lines.append(content)
                case .groupHeader(_, _, let title, _, _):
                    lines.append("[\(title)]")
                case .stepHeader(_, let name, _, _):
                    lines.append("== \(name) ==")
                }
            }
            return lines.joined(separator: "\n")
        }

        // MARK: - NSTableViewDataSource

        func numberOfRows(in tableView: NSTableView) -> Int {
            displayRows.count
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < displayRows.count else { return nil }

            switch displayRows[row] {
            case .stepHeader(let id, let name, let count, let isExpanded):
                return makeStepHeaderCell(id: id, name: name, count: count, isExpanded: isExpanded, tableView: tableView)
            case .groupHeader(let id, let stepId, let title, let count, let isExpanded):
                return makeGroupHeaderCell(id: id, stepId: stepId, title: title, count: count, isExpanded: isExpanded, tableView: tableView)
            case .logLine(_, _, let attributed):
                return makeLogLineCell(attributed: attributed, tableView: tableView)
            }
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < displayRows.count else { return 18 }
            switch displayRows[row] {
            case .stepHeader: return 28
            case .groupHeader: return 22
            case .logLine: return 18
            }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let rowView = LogRowView()
            if row < displayRows.count {
                switch displayRows[row] {
                case .stepHeader: rowView.isHeader = true; rowView.isStepHeader = true
                case .groupHeader: rowView.isHeader = true; rowView.isStepHeader = false
                case .logLine: rowView.isHeader = false
                }
            }
            return rowView
        }

        private func makeStepHeaderCell(id: Int, name: String, count: Int, isExpanded: Bool, tableView: NSTableView) -> NSView {
            let cellId = NSUserInterfaceItemIdentifier("StepHeader")
            let cell: StepHeaderCellView
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? StepHeaderCellView {
                cell = existing
            } else {
                cell = StepHeaderCellView(identifier: cellId)
            }
            cell.configure(id: id, name: name, count: count, isExpanded: isExpanded, fontSize: fontSize, onToggle: { [weak self] stepId in
                self?.toggleStep(stepId)
            }, onCopy: { [weak self] stepId in
                self?.copyStepLogs(stepId)
            })
            return cell
        }

        private func makeGroupHeaderCell(id: Int, stepId: Int, title: String, count: Int, isExpanded: Bool, tableView: NSTableView) -> NSView {
            let cellId = NSUserInterfaceItemIdentifier("GroupHeader")
            let cell: GroupHeaderCellView
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? GroupHeaderCellView {
                cell = existing
            } else {
                cell = GroupHeaderCellView(identifier: cellId)
            }
            cell.configure(id: id, stepId: stepId, title: title, count: count, isExpanded: isExpanded, fontSize: fontSize) { [weak self] groupId, stepId in
                self?.toggleGroup(groupId, inStep: stepId)
            }
            return cell
        }

        private func makeLogLineCell(attributed: NSAttributedString, tableView: NSTableView) -> NSView {
            let cellId = NSUserInterfaceItemIdentifier("LogLine")
            let cell: LogLineCellView
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? LogLineCellView {
                cell = existing
            } else {
                cell = LogLineCellView(identifier: cellId)
            }
            cell.configure(attributed: attributed)
            return cell
        }
    }
}

// MARK: - SwiftUI Wrapper

struct WorkflowLogView: View {
    let logs: String
    let fontSize: CGFloat

    @State private var showTimestamps: Bool = false

    init(_ logs: String, fontSize: CGFloat = 11, showStepNavigation: Bool = true) {
        self.logs = logs
        self.fontSize = fontSize
    }

    var body: some View {
        WorkflowLogTableView(logs: logs, fontSize: fontSize, showTimestamps: $showTimestamps, onCoordinatorReady: nil)
            .background(Color(nsColor: .textBackgroundColor))
    }
}

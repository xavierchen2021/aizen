//
//  TerminalSplitActions.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

// MARK: - Terminal Split Actions (for keyboard shortcuts)

struct TerminalSplitActions {
    let splitHorizontal: () -> Void
    let splitVertical: () -> Void
    let closePane: () -> Void
}

private struct TerminalSplitActionsKey: FocusedValueKey {
    typealias Value = TerminalSplitActions
}

extension FocusedValues {
    var terminalSplitActions: TerminalSplitActions? {
        get { self[TerminalSplitActionsKey.self] }
        set { self[TerminalSplitActionsKey.self] = newValue }
    }
}

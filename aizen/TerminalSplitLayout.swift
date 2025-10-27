//
//  TerminalSplitLayout.swift
//  aizen
//
//  Data structures for terminal split pane layout
//

import Foundation

indirect enum SplitNode: Codable, Equatable {
    case leaf(paneId: String)
    case hsplit(ratio: Double, left: SplitNode, right: SplitNode)
    case vsplit(ratio: Double, top: SplitNode, bottom: SplitNode)

    enum CodingKeys: String, CodingKey {
        case type, paneId, ratio, left, right, top, bottom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "leaf":
            let id = try container.decode(String.self, forKey: .paneId)
            self = .leaf(paneId: id)
        case "hsplit":
            let ratio = try container.decode(Double.self, forKey: .ratio)
            let left = try container.decode(SplitNode.self, forKey: .left)
            let right = try container.decode(SplitNode.self, forKey: .right)
            self = .hsplit(ratio: ratio, left: left, right: right)
        case "vsplit":
            let ratio = try container.decode(Double.self, forKey: .ratio)
            let top = try container.decode(SplitNode.self, forKey: .top)
            let bottom = try container.decode(SplitNode.self, forKey: .bottom)
            self = .vsplit(ratio: ratio, top: top, bottom: bottom)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid split type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .leaf(let paneId):
            try container.encode("leaf", forKey: .type)
            try container.encode(paneId, forKey: .paneId)
        case .hsplit(let ratio, let left, let right):
            try container.encode("hsplit", forKey: .type)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case .vsplit(let ratio, let top, let bottom):
            try container.encode("vsplit", forKey: .type)
            try container.encode(ratio, forKey: .ratio)
            try container.encode(top, forKey: .top)
            try container.encode(bottom, forKey: .bottom)
        }
    }

    // Get all pane IDs in the tree
    func allPaneIds() -> [String] {
        switch self {
        case .leaf(let paneId):
            return [paneId]
        case .hsplit(_, let left, let right):
            return left.allPaneIds() + right.allPaneIds()
        case .vsplit(_, let top, let bottom):
            return top.allPaneIds() + bottom.allPaneIds()
        }
    }

    // Find and replace a pane with a split
    func replacingPane(_ targetId: String, with newNode: SplitNode) -> SplitNode {
        switch self {
        case .leaf(let paneId):
            return paneId == targetId ? newNode : self
        case .hsplit(let ratio, let left, let right):
            return .hsplit(
                ratio: ratio,
                left: left.replacingPane(targetId, with: newNode),
                right: right.replacingPane(targetId, with: newNode)
            )
        case .vsplit(let ratio, let top, let bottom):
            return .vsplit(
                ratio: ratio,
                top: top.replacingPane(targetId, with: newNode),
                bottom: bottom.replacingPane(targetId, with: newNode)
            )
        }
    }

    // Remove a pane from the tree
    func removingPane(_ targetId: String) -> SplitNode? {
        switch self {
        case .leaf(let paneId):
            return paneId == targetId ? nil : self
        case .hsplit(_, let left, let right):
            let newLeft = left.removingPane(targetId)
            let newRight = right.removingPane(targetId)

            if newLeft == nil {
                return newRight
            }
            if newRight == nil {
                return newLeft
            }
            return .hsplit(ratio: 0.5, left: newLeft!, right: newRight!)
        case .vsplit(_, let top, let bottom):
            let newTop = top.removingPane(targetId)
            let newBottom = bottom.removingPane(targetId)

            if newTop == nil {
                return newBottom
            }
            if newBottom == nil {
                return newTop
            }
            return .vsplit(ratio: 0.5, top: newTop!, bottom: newBottom!)
        }
    }
}

// Helper for encoding/decoding layout to JSON
struct SplitLayoutHelper {
    static func encode(_ node: SplitNode) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(node),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func decode(_ json: String) -> SplitNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(SplitNode.self, from: data)
    }

    static func createDefault() -> SplitNode {
        return .leaf(paneId: UUID().uuidString)
    }
}

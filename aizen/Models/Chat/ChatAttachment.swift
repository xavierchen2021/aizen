//
//  ChatAttachment.swift
//  aizen
//
//  Attachment types for chat messages
//

import Foundation

enum ChatAttachment: Identifiable, Hashable {
    case file(URL)
    case reviewComments(String) // markdown content
    case buildError(String) // build error log

    var id: String {
        switch self {
        case .file(let url):
            return "file-\(url.absoluteString)"
        case .reviewComments(let content):
            return "review-\(content.hashValue)"
        case .buildError(let content):
            return "build-\(content.hashValue)"
        }
    }

    var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .reviewComments:
            return "Review Comments"
        case .buildError:
            return "Build Error"
        }
    }

    var iconName: String {
        switch self {
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "png", "jpg", "jpeg", "gif", "webp", "heic":
                return "photo"
            case "pdf":
                return "doc.richtext"
            case "swift", "js", "ts", "py", "rb", "go", "rs":
                return "doc.text"
            default:
                return "doc"
            }
        case .reviewComments:
            return "text.bubble"
        case .buildError:
            return "xmark.circle.fill"
        }
    }

    // For sending to agent - returns the content to include in message
    var contentForAgent: String? {
        switch self {
        case .file:
            // Files are handled separately by the agent protocol
            return nil
        case .reviewComments(let content):
            return content
        case .buildError(let content):
            return content
        }
    }

    // Get file URL if this is a file attachment
    var fileURL: URL? {
        if case .file(let url) = self {
            return url
        }
        return nil
    }
}

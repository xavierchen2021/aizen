import Foundation

enum MergeResult: Equatable {
    case success
    case conflict(files: [String])
    case alreadyUpToDate
}

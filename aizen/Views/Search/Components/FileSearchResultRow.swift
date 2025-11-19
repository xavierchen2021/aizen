//
//  FileSearchResultRow.swift
//  aizen
//
//  Created on 2025-11-19.
//

import SwiftUI

struct FileSearchResultRow: View {
    let result: FileSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // File icon
            FileIconView(path: result.path, size: 16)

            VStack(alignment: .leading, spacing: 2) {
                // File name
                Text(result.name)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : .primary)

                // Relative path
                Text(result.relativePath)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

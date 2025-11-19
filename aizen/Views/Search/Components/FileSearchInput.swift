//
//  FileSearchInput.swift
//  aizen
//
//  Created on 2025-11-19.
//

import SwiftUI

struct FileSearchInput: View {
    @Binding var searchQuery: String
    @FocusState.Binding var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))

            TextField("Search files...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

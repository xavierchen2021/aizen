//
//  SFSymbolPickerView.swift
//  aizen
//
//  SF Symbol picker for custom agent icons
//

import SwiftUI

struct SFSymbolPickerView: View {
    @Binding var selectedSymbol: String
    @Binding var isPresented: Bool
    @State private var searchText = ""

    // Popular symbols for quick access
    private let popularSymbols = [
        "brain.head.profile", "cpu", "terminal", "command", "gearshape",
        "bolt", "star", "sparkle", "wand.and.stars", "lightbulb",
        "flame", "cloud", "server.rack", "desktopcomputer", "laptopcomputer",
        "iphone", "atom", "swift", "python", "curlybraces",
        "text.bubble", "message", "envelope", "paperplane", "arrow.up.circle",
        "checkmark.circle", "xmark.circle", "exclamationmark.triangle", "questionmark.circle",
        "person", "person.2", "person.3", "folder", "doc.text"
    ]

    private var filteredSymbols: [String] {
        if searchText.isEmpty {
            return popularSymbols
        }
        return popularSymbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search symbols...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .buttonStyle(.borderless)
                }

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }

            // Symbol grid
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button(action: {
                            selectedSymbol = symbol
                            isPresented = false
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: symbol)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                                    .foregroundColor(selectedSymbol == symbol ? .white : .primary)

                                Text(symbol.split(separator: ".").first.map(String.init) ?? symbol)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .foregroundColor(selectedSymbol == symbol ? .white : .secondary)
                            }
                            .frame(width: 60, height: 60)
                            .background(selectedSymbol == symbol ? Color.accentColor : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(8)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }
}

//
//  TerminalSettingsView.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI

struct TerminalSettingsView: View {
    @Binding var fontName: String
    @Binding var fontSize: Double
    @AppStorage("terminalThemeName") private var themeName = "Catppuccin Mocha"

    @State private var availableFonts: [String] = []
    @State private var themeNames: [String] = []

    private static var themesPath: String? {
        guard let resourcePath = Bundle.main.resourcePath else { return nil }
        return (resourcePath as NSString).appendingPathComponent("ghostty/themes")
    }

    private func loadSystemFonts() -> [String] {
        let fontManager = NSFontManager.shared
        let monospaceFonts = fontManager.availableFontFamilies.filter { familyName in
            guard let font = NSFont(name: familyName, size: 12) else { return false }
            return font.isFixedPitch
        }
        return monospaceFonts.sorted()
    }

    private func loadThemeNames() -> [String] {
        guard let themesPath = Self.themesPath else {
            print("Error: Unable to locate themes directory")
            return []
        }

        guard let themeFiles = try? FileManager.default.contentsOfDirectory(atPath: themesPath) else {
            print("Error: Unable to read themes from \(themesPath)")
            return []
        }

        // Filter out directories and hidden files
        return themeFiles.filter { file in
            let path = (themesPath as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return !isDir.boolValue && !file.hasPrefix(".")
        }.sorted()
    }

    var body: some View {
        Form {
            Section(LocalizedStringKey("settings.terminal.font.section")) {
                Picker(LocalizedStringKey("settings.terminal.font.picker"), selection: $fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .disabled(availableFonts.isEmpty)

                HStack {
                    Text(String(format: NSLocalizedString("settings.terminal.font.size", comment: ""), Int(fontSize)))
                        .frame(width: 120, alignment: .leading)

                    Slider(value: $fontSize, in: 8...24, step: 1)

                    Stepper("", value: $fontSize, in: 8...24, step: 1)
                        .labelsHidden()
                }
            }

            Section(LocalizedStringKey("settings.terminal.theme.section")) {
                Picker(LocalizedStringKey("settings.terminal.theme.picker"), selection: $themeName) {
                    ForEach(themeNames, id: \.self) { theme in
                        Text(theme).tag(theme)
                    }
                }
                .disabled(themeNames.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if availableFonts.isEmpty {
                availableFonts = loadSystemFonts()
            }
            if themeNames.isEmpty {
                themeNames = loadThemeNames()
            }
        }
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

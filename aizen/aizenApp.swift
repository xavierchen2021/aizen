//
//  aizenApp.swift
//  aizen
//
//  Created by Uladzislau Yakauleu on 17.10.25.
//

import SwiftUI
import CoreData

@main
struct aizenApp: App {
    let persistenceController = PersistenceController.shared
    @FocusedValue(\.terminalSplitActions) private var splitActions
    @FocusedValue(\.chatActions) private var chatActions

    var body: some Scene {
        WindowGroup {
            ContentView(context: persistenceController.container.viewContext)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Split Right") {
                    splitActions?.splitHorizontal()
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Split Down") {
                    splitActions?.splitVertical()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Close Pane") {
                    splitActions?.closePane()
                }
                .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Cycle Mode") {
                    chatActions?.cycleModeForward()
                }
                .keyboardShortcut(.tab, modifiers: .shift)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage("defaultEditor") private var defaultEditor = "code"
    @AppStorage("defaultACPAgent") private var defaultACPAgent = "claude"
    @AppStorage("acpAgentPath_claude") private var claudePath = ""
    @AppStorage("acpAgentPath_codex") private var codexPath = ""
    @AppStorage("acpAgentPath_gemini") private var geminiPath = ""
    @AppStorage("terminalFontName") private var terminalFontName = "Menlo"
    @AppStorage("terminalFontSize") private var terminalFontSize = 12.0
    @AppStorage("terminalBackgroundColor") private var terminalBackgroundColor = "#1e1e2e"
    @AppStorage("terminalForegroundColor") private var terminalForegroundColor = "#cdd6f4"
    @AppStorage("terminalCursorColor") private var terminalCursorColor = "#f5e0dc"
    @AppStorage("terminalSelectionBackground") private var terminalSelectionBackground = "#585b70"
    @AppStorage("terminalPalette") private var terminalPalette = "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"

    @State private var testingAgent: String? = nil
    @State private var testResult: String? = nil

    var body: some View {
        TabView {
            GeneralSettingsView(defaultEditor: $defaultEditor)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag("general")

            TerminalSettingsView(
                fontName: $terminalFontName,
                fontSize: $terminalFontSize,
                backgroundColor: $terminalBackgroundColor,
                foregroundColor: $terminalForegroundColor,
                cursorColor: $terminalCursorColor,
                selectionBackground: $terminalSelectionBackground,
                palette: $terminalPalette
            )
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
            .tag("terminal")

            AgentsSettingsView(
                defaultACPAgent: $defaultACPAgent,
                claudePath: $claudePath,
                codexPath: $codexPath,
                geminiPath: $geminiPath,
                testingAgent: $testingAgent,
                testResult: $testResult
            )
            .tabItem {
                Label("Agents", systemImage: "brain")
            }
            .tag("agents")
        }
        .frame(width: 600, height: 600)
    }
}

struct GeneralSettingsView: View {
    @Binding var defaultEditor: String

    var body: some View {
        Form {
            Section("Editor") {
                TextField("Default Editor Command", text: $defaultEditor)
                    .help("Command to launch your preferred code editor (e.g., 'code', 'cursor', 'subl')")

                Text("Common editors: code (VS Code), cursor (Cursor), subl (Sublime), atom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TerminalTheme {
    let name: String
    let bg: String
    let fg: String
    let cursor: String
    let selection: String
    let palette: String
}

struct TerminalSettingsView: View {
    @Binding var fontName: String
    @Binding var fontSize: Double
    @Binding var backgroundColor: String
    @Binding var foregroundColor: String
    @Binding var cursorColor: String
    @Binding var selectionBackground: String
    @Binding var palette: String

    private let availableFonts = [
        "Menlo",
        "Monaco",
        "Courier New",
        "SF Mono",
        "JetBrainsMono Nerd Font",
        "FiraCode Nerd Font",
        "Hack Nerd Font",
        "MesloLGS NF"
    ]

    private let themes: [TerminalTheme] = [
        TerminalTheme(name: "Catppuccin Mocha", bg: "#1e1e2e", fg: "#cdd6f4", cursor: "#f5e0dc", selection: "#585b70", palette: "#45475a,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#f5c2e7,#94e2d5,#a6adc8,#585b70,#f37799,#89d88b,#ebd391,#74a8fc,#f2aede,#6bd7ca,#bac2de"),
        TerminalTheme(name: "Catppuccin Frappe", bg: "#303446", fg: "#c6d0f5", cursor: "#f2d5cf", selection: "#626880", palette: "#51576d,#e78284,#a6d189,#e5c890,#8caaee,#f4b8e4,#81c8be,#a5adce,#626880,#e67172,#8ec772,#d9ba73,#7b9ef0,#f2a4db,#5abfb5,#b5bfe2"),
        TerminalTheme(name: "Catppuccin Latte", bg: "#eff1f5", fg: "#4c4f69", cursor: "#dc8a78", selection: "#acb0be", palette: "#5c5f77,#d20f39,#40a02b,#df8e1d,#1e66f5,#ea76cb,#179299,#acb0be,#6c6f85,#de293e,#49af3d,#eea02d,#456eff,#fe85d8,#2d9fa8,#bcc0cc"),
        TerminalTheme(name: "Catppuccin Macchiato", bg: "#24273a", fg: "#cad3f5", cursor: "#f4dbd6", selection: "#5b6078", palette: "#494d64,#ed8796,#a6da95,#eed49f,#8aadf4,#f5bde6,#8bd5ca,#a5adcb,#5b6078,#ec7486,#8ccf7f,#e1c682,#78a1f6,#f2a9dd,#63cbc0,#b8c0e0"),
        TerminalTheme(name: "Dracula", bg: "#282a36", fg: "#f8f8f2", cursor: "#f8f8f2", selection: "#44475a", palette: "#21222c,#ff5555,#50fa7b,#f1fa8c,#bd93f9,#ff79c6,#8be9fd,#f8f8f2,#6272a4,#ff6e6e,#69ff94,#ffffa5,#d6acff,#ff92df,#a4ffff,#ffffff"),
        TerminalTheme(name: "Nord", bg: "#2e3440", fg: "#d8dee9", cursor: "#eceff4", selection: "#eceff4", palette: "#3b4252,#bf616a,#a3be8c,#ebcb8b,#81a1c1,#b48ead,#88c0d0,#e5e9f0,#596377,#bf616a,#a3be8c,#ebcb8b,#81a1c1,#b48ead,#8fbcbb,#eceff4"),
        TerminalTheme(name: "Gruvbox Dark", bg: "#282828", fg: "#ebdbb2", cursor: "#ebdbb2", selection: "#665c54", palette: "#282828,#cc241d,#98971a,#d79921,#458588,#b16286,#689d6a,#a89984,#928374,#fb4934,#b8bb26,#fabd2f,#83a598,#d3869b,#8ec07c,#ebdbb2"),
        TerminalTheme(name: "Gruvbox Light", bg: "#fbf1c7", fg: "#3c3836", cursor: "#3c3836", selection: "#3c3836", palette: "#fbf1c7,#cc241d,#98971a,#d79921,#458588,#b16286,#689d6a,#7c6f64,#928374,#9d0006,#79740e,#b57614,#076678,#8f3f71,#427b58,#3c3836"),
        TerminalTheme(name: "TokyoNight", bg: "#1a1b26", fg: "#c0caf5", cursor: "#c0caf5", selection: "#33467c", palette: "#15161e,#f7768e,#9ece6a,#e0af68,#7aa2f7,#bb9af7,#7dcfff,#a9b1d6,#414868,#f7768e,#9ece6a,#e0af68,#7aa2f7,#bb9af7,#7dcfff,#c0caf5"),
        TerminalTheme(name: "TokyoNight Storm", bg: "#24283b", fg: "#c0caf5", cursor: "#c0caf5", selection: "#364a82", palette: "#1d202f,#f7768e,#9ece6a,#e0af68,#7aa2f7,#bb9af7,#7dcfff,#a9b1d6,#4e5575,#f7768e,#9ece6a,#e0af68,#7aa2f7,#bb9af7,#7dcfff,#c0caf5"),
        TerminalTheme(name: "Monokai Pro", bg: "#2d2a2e", fg: "#fcfcfa", cursor: "#c1c0c0", selection: "#5b595c", palette: "#2d2a2e,#ff6188,#a9dc76,#ffd866,#fc9867,#ab9df2,#78dce8,#fcfcfa,#727072,#ff6188,#a9dc76,#ffd866,#fc9867,#ab9df2,#78dce8,#fcfcfa"),
        TerminalTheme(name: "Solarized Dark High Contrast", bg: "#001e27", fg: "#9cc2c3", cursor: "#f34b00", selection: "#003748", palette: "#002831,#d11c24,#6cbe6c,#a57706,#2176c7,#c61c6f,#259286,#eae3cb,#006488,#f5163b,#51ef84,#b27e28,#178ec8,#e24d8e,#00b39e,#fcf4dc"),
        TerminalTheme(name: "Solarized Light", bg: "#fdf6e3", fg: "#657b83", cursor: "#657b83", selection: "#eee8d5", palette: "#073642,#dc322f,#859900,#b58900,#268bd2,#d33682,#2aa198,#bbb5a2,#002b36,#cb4b16,#586e75,#657b83,#839496,#6c71c4,#93a1a1,#fdf6e3")
    ]

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font", selection: $fontName) {
                    ForEach(availableFonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }

                HStack {
                    Text("Font Size: \(Int(fontSize))")
                        .frame(width: 120, alignment: .leading)

                    Slider(value: $fontSize, in: 8...24, step: 1)

                    Stepper("", value: $fontSize, in: 8...24, step: 1)
                        .labelsHidden()
                }
            }

            Section("Colors") {
                Picker("Theme", selection: Binding(
                    get: {
                        themes.first(where: { $0.bg == backgroundColor && $0.fg == foregroundColor && $0.palette == palette })?.name ?? "Custom"
                    },
                    set: { newValue in
                        if let theme = themes.first(where: { $0.name == newValue }) {
                            backgroundColor = theme.bg
                            foregroundColor = theme.fg
                            cursorColor = theme.cursor
                            selectionBackground = theme.selection
                            palette = theme.palette
                        }
                    }
                )) {
                    ForEach(themes, id: \.name) { theme in
                        Text(theme.name).tag(theme.name)
                    }
                    Text("Custom").tag("Custom")
                }

                HStack {
                    Text("Background")
                        .frame(width: 100, alignment: .leading)

                    ColorPicker("", selection: Binding(
                        get: { Color(hex: backgroundColor) ?? Color.black },
                        set: { backgroundColor = $0.toHex() }
                    ))
                    .labelsHidden()

                    TextField("Hex", text: $backgroundColor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Foreground")
                        .frame(width: 100, alignment: .leading)

                    ColorPicker("", selection: Binding(
                        get: { Color(hex: foregroundColor) ?? Color.white },
                        set: { foregroundColor = $0.toHex() }
                    ))
                    .labelsHidden()

                    TextField("Hex", text: $foregroundColor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Cursor")
                        .frame(width: 100, alignment: .leading)

                    ColorPicker("", selection: Binding(
                        get: { Color(hex: cursorColor) ?? Color.white },
                        set: { cursorColor = $0.toHex() }
                    ))
                    .labelsHidden()

                    TextField("Hex", text: $cursorColor)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Selection")
                        .frame(width: 100, alignment: .leading)

                    ColorPicker("", selection: Binding(
                        get: { Color(hex: selectionBackground) ?? Color.gray },
                        set: { selectionBackground = $0.toHex() }
                    ))
                    .labelsHidden()

                    TextField("Hex", text: $selectionBackground)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }

            Section("Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ ls -la")
                        .font(.custom(fontName, size: fontSize))
                    Text("total 48")
                        .font(.custom(fontName, size: fontSize))
                    Text("drwxr-xr-x  12 user  staff   384 Oct 17 12:00 .")
                        .font(.custom(fontName, size: fontSize))
                    Text("$ echo \"Hello World\"")
                        .font(.custom(fontName, size: fontSize))
                    Text("Hello World")
                        .font(.custom(fontName, size: fontSize))
                }
                .foregroundColor(Color(hex: foregroundColor) ?? .white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: backgroundColor) ?? .black, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .formStyle(.grouped)
        .padding()
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

struct AgentsSettingsView: View {
    @Binding var defaultACPAgent: String
    @Binding var claudePath: String
    @Binding var codexPath: String
    @Binding var geminiPath: String
    @Binding var testingAgent: String?
    @Binding var testResult: String?

    var body: some View {
        Form {
            Section("Agents") {
                VStack(alignment: .leading, spacing: 16) {
                    // Claude Agent
                    AgentConfigView(
                        agentName: "claude",
                        agentPath: $claudePath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Codex Agent
                    AgentConfigView(
                        agentName: "codex",
                        agentPath: $codexPath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Gemini Agent
                    AgentConfigView(
                        agentName: "gemini",
                        agentPath: $geminiPath,
                        testingAgent: $testingAgent,
                        testResult: $testResult
                    )

                    Divider()

                    // Default Agent Picker
                    HStack {
                        Text("Default Agent:")
                            .frame(width: 100, alignment: .leading)

                        Picker("", selection: $defaultACPAgent) {
                            Text("Claude").tag("claude")
                            Text("Codex").tag("codex")
                            Text("Gemini").tag("gemini")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AgentConfigView: View {
    let agentName: String
    @Binding var agentPath: String
    @Binding var testingAgent: String?
    @Binding var testResult: String?

    @State private var isValid: Bool = false
    @State private var isInstalling: Bool = false
    @State private var installError: String?

    var body: some View {
        GroupBox(label: Text(agentName.capitalized).font(.headline)) {
            VStack(spacing: 12) {
                HStack {
                    TextField("Executable Path", text: $agentPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentPath) { _, newValue in
                            syncToRegistry()
                            validatePath()
                        }

                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                        .opacity(agentPath.isEmpty ? 0 : 1)
                }

                HStack {
                    if !isValid {
                        Button(isInstalling ? "Installing..." : "Install") {
                            installAgent()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isInstalling)

                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    } else {
                        Button("Test Connection") {
                            testConnection()
                        }
                        .buttonStyle(.bordered)

                        if testingAgent == agentName {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        if let result = testResult, testingAgent == agentName {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                        }
                    }

                    if let error = installError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }

                    Spacer()
                }
            }
            .padding(8)
        }
        .onAppear {
            loadFromRegistry()
            validatePath()
        }
    }

    private func loadFromRegistry() {
        if let path = AgentRegistry.shared.getAgentPath(for: agentName) {
            agentPath = path
        }
    }

    private func syncToRegistry() {
        if !agentPath.isEmpty {
            AgentRegistry.shared.setAgentPath(agentPath, for: agentName)
        }
    }

    private func validatePath() {
        isValid = AgentRegistry.shared.validateAgent(named: agentName)
    }

    private func installAgent() {
        isInstalling = true
        installError = nil

        Task {
            do {
                try await AgentInstaller.shared.installAgent(agentName)
                let execPath = await AgentInstaller.shared.getAgentExecutablePath(agentName)
                await MainActor.run {
                    agentPath = execPath
                    validatePath()
                    isInstalling = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isInstalling = false
                }
            }
        }
    }

    private func testConnection() {
        guard !agentPath.isEmpty else { return }

        testingAgent = agentName
        testResult = nil

        Task {
            // Simple validation: check if file exists and is executable
            let fileManager = FileManager.default
            let exists = fileManager.fileExists(atPath: agentPath)
            let executable = fileManager.isExecutableFile(atPath: agentPath)

            if exists && executable {
                // Try running --version for agents that support it (codex, gemini)
                if agentName != "claude" {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: agentPath)
                    process.arguments = ["--version"]

                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = pipe

                    do {
                        try process.run()
                        process.waitUntilExit()

                        await MainActor.run {
                            testResult = process.terminationStatus == 0 ? "Success" : "Failed"
                        }
                    } catch {
                        await MainActor.run {
                            testResult = "Error"
                        }
                    }
                } else {
                    // For claude, just verify file validity
                    await MainActor.run {
                        testResult = "Success"
                    }
                }
            } else {
                await MainActor.run {
                    testResult = "Invalid"
                }
            }

            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if testingAgent == agentName {
                        testingAgent = nil
                        testResult = nil
                    }
                }
            }
        }
    }
}

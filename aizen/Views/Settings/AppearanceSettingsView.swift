import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("showChatTab") private var showChatTab = true
    @AppStorage("showTerminalTab") private var showTerminalTab = true
    @AppStorage("showFilesTab") private var showFilesTab = true
    @AppStorage("showBrowserTab") private var showBrowserTab = true
    @AppStorage("showOpenInApp") private var showOpenInApp = true
    @AppStorage("showGitStatus") private var showGitStatus = true
    @AppStorage("showXcodeBuild") private var showXcodeBuild = true

    var body: some View {
        Form {
            Section {
                Toggle("Chat", isOn: $showChatTab)
                    .help("Hide the Chat tab in worktree views")

                Toggle("Terminal", isOn: $showTerminalTab)
                    .help("Hide the Terminal tab in worktree views")

                Toggle("Files", isOn: $showFilesTab)
                    .help("Hide the Files tab in worktree views")

                Toggle("Browser", isOn: $showBrowserTab)
                    .help("Hide the Browser tab in worktree views")
            } header: {
                Text("Worktree Tabs")
            }

            Section {
                Toggle("Open in External App", isOn: $showOpenInApp)
                    .help("Hide the 'Open in...' button for opening worktree in third-party apps like Finder")

                Toggle("Git Status", isOn: $showGitStatus)
                    .help("Hide the Git status indicator showing changes")

                Toggle("Xcode Build", isOn: $showXcodeBuild)
                    .help("Show Xcode build button for projects with .xcodeproj or .xcworkspace")
            } header: {
                Text("Toolbar Items")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

#Preview {
    AppearanceSettingsView()
}

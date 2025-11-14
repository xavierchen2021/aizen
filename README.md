# Aizen

Manage multiple Git branches simultaneously with dedicated terminals and agents in parallel.

![Aizen Demo](https://r2.aizen.win/demo.png)

## Features

- **Workspace Management**: Organize repositories into workspaces
- **Git Worktree Support**: Create and manage Git worktrees with visual UI
- **Integrated Terminal**: GPU-accelerated terminal with libghostty and split pane support
- **AI Agent Integration**: Support for Claude, Codex, Gemini, and Kimi via Agent Client Protocol (ACP)
- **Voice Input**: Voice recording with live waveform visualization and speech-to-text transcription
- **Git Operations**: Integrated sidebar for staging, committing, pushing, pulling, and branch management
- **Agent Management**: Automatic agent discovery and installation (NPM, GitHub releases)
- **Automatic Updates**: Built-in update system via Sparkle
- **Markdown Rendering**: View and render markdown content with syntax highlighting
- **Custom Agents**: Add and configure custom ACP-compatible agents

## Requirements

- macOS 13.5+
- Xcode 16.0+ (for building from source)
- Swift 5.0+ (for building from source)

## Dependencies

- [libghostty](https://github.com/ghostty-org/ghostty) - GPU-accelerated terminal emulator
- [swift-markdown](https://github.com/apple/swift-markdown) - Markdown parsing
- [swift-cmark](https://github.com/apple/swift-cmark) - CommonMark parsing (dependency of swift-markdown)
- [HighlightSwift](https://github.com/appstefan/highlightswift) (1.1.0+) - Syntax highlighting
- [Sparkle](https://github.com/sparkle-project/Sparkle) (2.8.0+) - Automatic updates

## Installation

Download the latest release from [aizen.win](https://aizen.win).

The app is signed and notarized with an Apple Developer certificate.

### Build from Source

1. Clone the repository with Git LFS support:
   ```bash
   git lfs install
   git clone https://github.com/vivy-company/aizen.git
   ```
2. Open `aizen.xcodeproj` in Xcode
3. Build and run

## Configuration

### Terminal Settings

Configure terminal appearance in Settings:
- Font and size
- Color themes (Catppuccin, Dracula, Nord, Gruvbox, TokyoNight, etc.)
- Custom color palettes

### AI Agents

Set up AI agents in Settings > Agents:
- **Claude**: Installed via NPM (`@zed-industries/claude-code-acp`)
- **Codex**: Installed via GitHub releases (`openai/openai-agent`)
- **Gemini**: Installed via NPM (`@google/gemini-cli` with `--experimental-acp`)
- **Kimi**: Installed via GitHub releases (`MoonshotAI/kimi-cli`)
- **Custom Agents**: Add custom ACP-compatible agents

The app can automatically discover and install agents, or you can manually configure paths.

### Editor

Configure default code editor in Settings > General:
- VS Code (`code`)
- Cursor (`cursor`)
- Sublime Text (`subl`)

### Updates

Automatic update checks via Sparkle. Configure in Settings > Updates.

## Usage

### Basic Workflow

1. **Create a workspace**: Organize your projects
2. **Add Git repositories**: Link repositories to workspaces
3. **Create worktrees**: Work on multiple branches simultaneously
4. **Open terminals**: Access integrated terminal in worktree directories
5. **Use AI agents**: Get code assistance via chat interface
6. **Voice input**: Use microphone for voice-to-text in chat
7. **Git operations**: Stage, commit, push/pull via integrated sidebar
8. **Branch management**: Switch branches or create new ones

### Terminal

- Split panes horizontally or vertically
- GPU-accelerated rendering via libghostty
- Multiple terminal tabs per worktree
- Configurable themes and fonts

### Chat & Agents

- Multiple chat modes (cycle with `⇧ ⇥`)
- Support for text and voice input
- Plan approval for complex operations
- Markdown rendering with syntax highlighting

## Keyboard Shortcuts

- `⌘ D` - Split terminal right
- `⌘ ⇧ D` - Split terminal down
- `⌘ W` - Close terminal pane
- `⇧ ⇥` - Cycle chat mode
- `ESC` - Interrupt running agent

## Development

### Project Structure

The codebase is organized by domain for better maintainability and scalability:

```
aizen/
├── App/
│   └── aizenApp.swift                    # App entry point and window management
│
├── Models/
│   ├── ACP/
│   │   └── ACPTypes.swift                # Agent Client Protocol type definitions
│   └── Agent/                            # Agent domain models
│
├── Services/
│   ├── Agent/
│   │   ├── ACP/                          # ACP protocol implementation
│   │   ├── Delegates/                    # Agent session delegates
│   │   ├── Installers/                   # Agent installation logic (NPM, GitHub)
│   │   ├── ACPClient.swift               # ACP subprocess communication
│   │   ├── AgentSession.swift            # Agent session state management
│   │   ├── AgentRegistry.swift           # Agent discovery and configuration
│   │   └── AgentRouter.swift             # Agent request routing
│   ├── Git/
│   │   ├── Core/                         # Core Git operations
│   │   ├── Domain/                       # Git domain models
│   │   ├── Repository/                   # Repository management
│   │   ├── GitService.swift              # Git command execution
│   │   └── RepositoryManager.swift       # Repository and worktree management
│   ├── Audio/                            # Audio recording and transcription
│   │   ├── AudioService.swift
│   │   ├── SpeechRecognitionService.swift
│   │   ├── AudioPermissionManager.swift
│   │   └── AudioRecordingService.swift
│   ├── Input/
│   │   └── KeyboardShortcutManager.swift # Global keyboard shortcuts
│   ├── Persistence/
│   │   └── Persistence.swift             # Core Data stack
│   └── AppDetector.swift                 # Installed app discovery
│
├── Views/
│   ├── ContentView.swift                 # Main navigation layout
│   ├── Onboarding/                       # First-time user onboarding
│   ├── Settings/
│   │   ├── SettingsView.swift            # Settings container
│   │   ├── GeneralSettingsView.swift     # Editor preferences
│   │   ├── TerminalSettingsView.swift    # Terminal configuration
│   │   ├── AgentsSettingsView.swift      # Agent setup
│   │   ├── UpdateSettingsView.swift      # Automatic update settings
│   │   └── AdvancedSettingsView.swift    # Advanced configuration
│   ├── Workspace/
│   │   ├── WorkspaceSidebarView.swift    # Workspace list sidebar
│   │   ├── WorkspaceCreateSheet.swift    # Workspace creation
│   │   └── WorkspaceEditSheet.swift      # Workspace editing
│   ├── Worktree/
│   │   ├── WorktreeListView.swift        # Worktree list
│   │   ├── WorktreeDetailView.swift      # Worktree details and actions
│   │   ├── WorktreeCreateSheet.swift     # Worktree creation
│   │   └── RepositoryAddSheet.swift      # Repository addition
│   ├── Changes/                          # Git changes sidebar
│   │   └── GitSidebarView.swift          # Stage/commit/push interface
│   ├── Chat/
│   │   ├── ChatTabView.swift             # Chat tab management
│   │   ├── ChatSessionView.swift         # Chat session interface
│   │   ├── MessageBubbleView.swift       # Message rendering
│   │   ├── ToolCallView.swift            # Tool execution status
│   │   ├── AgentIconView.swift           # Agent icon component
│   │   ├── ACPContentViews.swift         # ACP content rendering
│   │   ├── VoiceRecordingView.swift      # Voice input with waveform
│   │   ├── PlanApprovalDialog.swift      # Agent plan approval
│   │   └── Components/
│   │       ├── ChatInputView.swift       # Chat input field
│   │       ├── MarkdownContentView.swift # Markdown rendering
│   │       ├── CodeBlockView.swift       # Code block with syntax highlighting
│   │       └── ContentBlockView.swift    # Multi-type content blocks
│   └── Terminal/
│       ├── TerminalTabView.swift         # Terminal tab management
│       └── TerminalSplitLayout.swift     # Terminal pane splitting
│
├── GhosttyTerminal/                      # libghostty integration
│   └── Ghostty.*.swift                   # Terminal implementation
│
├── Managers/
│   ├── ChatSessionManager.swift          # Chat session lifecycle
│   └── ToastManager.swift                # Toast notification system
│
└── Utilities/
    ├── LanguageDetection.swift           # Code language detection
    └── WorkspaceNameGenerator.swift      # Random workspace names
```

### Architecture

- **MVVM Pattern**: Views observe `@ObservableObject` models
- **Actor Model**: Thread-safe concurrent operations (`ACPClient`, `GitService`)
- **Core Data**: Persistent storage for workspaces, repositories, worktrees
- **SwiftUI**: Declarative UI with modern Swift concurrency (async/await)

## License

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this software except in compliance with the License. You may obtain a copy of the License at:

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

Copyright © 2025 Vivy Technologies Co., Limited

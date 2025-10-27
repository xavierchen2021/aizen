# Aizen

A macOS developer tool for managing Git worktrees with integrated terminal and AI agent support.

## Features

- **Workspace Management**: Organize repositories into workspaces
- **Git Worktree Support**: Create and manage Git worktrees with visual UI
- **Integrated Terminal**: Split terminal panels with SwiftTerm
- **AI Agent Integration**: Support for Claude, Codex, and Gemini via Agent Client Protocol (ACP)
- **Markdown Rendering**: View and render markdown content
- **Syntax Highlighting**: Code highlighting with HighlightSwift

## Requirements

- macOS 26.0+
- Xcode 16.0+
- Swift 5.0+

## Dependencies

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulator
- [swift-markdown](https://github.com/apple/swift-markdown) - Markdown parsing
- [HighlightSwift](https://github.com/appstefan/highlightswift) - Syntax highlighting

## Installation

1. Clone the repository
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
- Claude: Install and configure path
- Codex: Install and configure path
- Gemini: Install and configure path

### Editor

Configure default code editor in Settings > General:
- VS Code (`code`)
- Cursor (`cursor`)
- Sublime Text (`subl`)

## Usage

1. Create a workspace
2. Add Git repositories
3. Create worktrees for different branches
4. Open terminals in worktree directories
5. Use AI agents for code assistance

## Keyboard Shortcuts

- `⌘ D` - Split terminal right
- `⌘ ⇧ D` - Split terminal down
- `⌘ W` - Close terminal pane
- `⇧ ⇥` - Cycle chat mode

## Development

### Project Structure

```
aizen/
├── ACPClient.swift          # Agent Client Protocol client
├── ACPTypes.swift           # ACP type definitions
├── ACPContentViews.swift    # ACP UI components
├── AgentRegistry.swift      # Agent management
├── AgentRouter.swift        # Agent routing logic
├── AgentSession.swift       # Agent session handling
├── AgentInstaller.swift     # Agent installation
├── ChatSessionManager.swift # Chat session state
├── ChatTabView.swift        # Chat interface
├── MessageBubbleView.swift  # Chat message UI
├── ToolCallView.swift       # Tool call visualization
├── RepositoryManager.swift  # Repository operations
├── WorkspaceManager.swift   # Workspace operations
├── GitService.swift         # Git operations
├── TerminalTabView.swift    # Terminal interface
├── TerminalSplitLayout.swift # Terminal split logic
└── ContentView.swift        # Main app view
```

## License

Copyright © 2025

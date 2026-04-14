<p align="center">
  <img src="https://raw.githubusercontent.com/Worth-Doing/brand-assets/main/png/variants/04-horizontal.png" alt="WorthDoing.ai" width="600" />
</p>

<p align="center">
  <img src="Resources/foundry-logo.svg" alt="Foundry Logo" width="200" />
</p>

<h1 align="center">Foundry</h1>

<p align="center">
  <strong>The Native Claude Code Interface for macOS</strong>
</p>

<p align="center">
  <a href="#installation"><img src="https://img.shields.io/badge/Platform-macOS%2014%2B-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Language-Swift%206.3-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/UI-SwiftUI-006AFF?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"></a>
  <a href="#"><img src="https://img.shields.io/badge/License-Proprietary-lightgrey?style=for-the-badge" alt="License"></a>
  <a href="#"><img src="https://img.shields.io/badge/Apple-Notarized-brightgreen?style=for-the-badge&logo=apple&logoColor=white" alt="Notarized"></a>
  <a href="#"><img src="https://img.shields.io/badge/Code%20Signed-Developer%20ID-green?style=for-the-badge&logo=apple&logoColor=white" alt="Signed"></a>
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/Architecture-arm64-informational?style=flat-square" alt="Arch"></a>
  <a href="#"><img src="https://img.shields.io/badge/Lines%20of%20Code-6%2C500%2B-blueviolet?style=flat-square" alt="LOC"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift%20Files-27-orange?style=flat-square" alt="Files"></a>
  <a href="#"><img src="https://img.shields.io/badge/Build%20System-SPM-red?style=flat-square" alt="SPM"></a>
  <a href="#"><img src="https://img.shields.io/badge/Made%20with-Claude%20Code-8A2BE2?style=flat-square" alt="Claude Code"></a>
</p>

---

<p align="center">
  <em>Built by <a href="https://worthdoing.ai">WorthDoing AI</a></em>
</p>

---

## Download

<p align="center">
  <a href="https://github.com/Worth-Doing/foundry/releases/download/v1.0.0/Foundry-1.0.0.dmg">
    <img src="https://img.shields.io/badge/⬇%20Download-Foundry%201.0.0%20DMG-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG">
  </a>
</p>

> **[📥 Foundry-1.0.0.dmg](https://github.com/Worth-Doing/foundry/releases/download/v1.0.0/Foundry-1.0.0.dmg)** — 2.5 MB | Apple Notarized | Code Signed | macOS 14+

---

## What is Foundry?

**Foundry** is a native macOS application that transforms [Claude Code](https://docs.anthropic.com/en/docs/claude-code) from an opaque CLI tool into a **visible, structured, and controllable system**.

Foundry is **not** a terminal emulator.  
Foundry is **not** a chatbot wrapper.  
Foundry is a **native execution environment** for Claude Code sessions.

> Claude Code becomes invisible. Foundry becomes the product.

### The Problem

Claude Code is extraordinarily powerful, but when used via the CLI:

- Agent activity is hard to follow in raw terminal output
- Session history is buried in hidden dotfiles
- Multi-session management requires multiple terminal tabs
- Token usage and costs are invisible
- File changes are hard to track
- Slash commands require memorization

### The Solution

Foundry gives you:

| Feature | Description |
|---------|-------------|
| 🏗️ **Structured Timeline** | Every action visualized — messages, tool calls, file edits, agent spawns |
| 💬 **Chat Interface** | Modern chat bubbles with Enter-to-send, Markdown rendering, code blocks |
| 📊 **Usage Analytics** | Real-time token counts, cost breakdown per session and total |
| 🔌 **MCP Management** | View, add, and remove MCP servers directly from the UI |
| 🤖 **Agent Viewer** | See all configured agents, add custom ones to settings.json |
| ⚡ **Skills Browser** | Browse all slash commands and marketplace plugins, install with one click |
| 📁 **File Tracking** | Monitor file changes with diff visualization |
| 🔄 **Multi-Session** | Run parallel Claude Code sessions, switch instantly |
| 🕐 **Full History** | Every Claude Code session ever run on your machine, loaded automatically |

---

## Screenshots

### Session Timeline with Chat Bubbles
The main view displays every event from your Claude Code session in a structured, scrollable timeline with chat-style message bubbles, collapsible tool calls, and inline file operation indicators.

### Command Palette
Press `⌘K` to open the command palette with access to every Claude Code slash command — `/commit`, `/review`, `/security-review`, `/simplify`, `/model`, `/memory`, and more.

### Usage & Costs Dashboard
Detailed token usage breakdown with visual bar charts, per-session cost table, and filterable time periods.

---

## Features

### 🖥️ Native macOS Experience

<table>
<tr>
<td width="50%">

**100% Native SwiftUI**
- No Electron, no web wrappers
- Hardware-accelerated rendering
- Native macOS controls and behaviors
- Respects system appearance (Light/Dark mode)
- Full keyboard navigation
- Retina display optimized

</td>
<td width="50%">

**Professional Developer Tool**
- NavigationSplitView with resizable panels
- Collapsible sidebar, file panel, terminal panel
- Global keyboard shortcuts
- Menu bar integration
- Settings window
- App icon in Dock

</td>
</tr>
</table>

---

### 💬 Modern Chat Interface

The conversation view is designed for productivity, not novelty:

- **Enter to send** — `Shift+Enter` for new line (custom `NSTextView` wrapper)
- **Chat bubbles** — user messages right-aligned in blue, Claude left-aligned with avatar
- **Full Markdown rendering** including:
  - `# Headings` at all levels
  - **Bold**, *italic*, `inline code`
  - Fenced code blocks with language label and **Copy button**
  - Bullet and numbered lists
  - Blockquotes with colored sidebar
  - Tables with striped rows
  - Horizontal rules
- **Animated typing indicator** (bouncing dots) when Claude is working
- **Processing bar** with real-time status and Stop button
- **Hover timestamps** on all messages

---

### 📊 Complete Claude Code Session History

Foundry reads **every session** directly from Claude Code's data files:

```
~/.claude/projects/*/                  # All project directories
  └── <session-id>.jsonl               # Full conversation logs (JSONL format)
```

**What gets loaded:**
- ✅ All sessions from all projects on the machine
- ✅ User messages and prompts
- ✅ Assistant responses with full Markdown
- ✅ Thinking blocks (collapsible)
- ✅ Tool use — Bash, Read, Write, Edit, Grep, Glob, Agent, etc.
- ✅ Tool results with collapsible output
- ✅ File operations (read/write/edit) with paths
- ✅ Search operations with patterns
- ✅ Sub-agent spawns with type and description
- ✅ Error events
- ✅ System events and permission mode changes
- ✅ Token usage per assistant message (input, output, cache read, cache write)

**Cost calculation** is computed automatically from token usage with model-specific pricing:

| Model | Input | Output | Cache Read | Cache Write |
|-------|-------|--------|------------|-------------|
| Opus 4.6 | $15.00/M | $75.00/M | $1.50/M | $18.75/M |
| Sonnet 4.6 | $3.00/M | $15.00/M | $0.30/M | $3.75/M |
| Haiku 4.5 | $0.80/M | $4.00/M | $0.08/M | $1.00/M |

---

### 🔄 Live Claude Code Integration

Send messages directly from Foundry — Claude Code runs in the background:

```
claude -p "<message>" --output-format stream-json --verbose --resume <session-id>
```

**How it works:**
1. You type a message and press Enter
2. Foundry spawns a Claude Code process with `--print --output-format stream-json --verbose`
3. Stream-JSON events are parsed in real time
4. Events appear in the timeline with proper formatting
5. Session ID is captured for `--resume` on next message
6. Token usage and costs are updated automatically

---

### ⌘K Command Palette

Every Claude Code slash command is accessible through the command palette:

| Category | Commands |
|----------|----------|
| **Session** | `/clear` · `/compact` · `/resume` · `/status` |
| **Code** | `/review` · `/simplify` · `/security-review` · `/init` |
| **Git** | `/commit` · `/pr-comments` |
| **Configuration** | `/config` · `/permissions` · `/model` · `/memory` · `/vim` · `/terminal-setup` |
| **Account** | `/login` · `/logout` |
| **Analysis** | `/cost` · `/insights` |
| **System** | `/help` · `/doctor` · `/bug` · `/schedule` · `/loop` |

---

### ⚡ Skills Management

Browse and install Claude Code skills and plugins:

- **Built-in skills** — `update-config`, `simplify`, `loop`, `schedule`, `claude-api`, `compact`, `init`, `review`, `security-review`, `insights`, `team-onboarding`, `commit`, `statusline`
- **Marketplace plugins** — Browse the `claude-plugins-official` marketplace
- **One-click install** — Install plugins directly from the UI
- **Status indicators** — See which skills are installed vs available

---

### 🤖 Agents Management

View and configure Claude Code agents:

- **Built-in agents** — `general-purpose`, `Explore` (haiku), `Plan`, `statusline-setup` (sonnet)
- **Custom agents** — Add your own with name, description, model, and system prompt
- **Saves to settings.json** — Custom agents persist in Claude Code's config

---

### 🔌 MCP Server Management

Full MCP (Model Context Protocol) server lifecycle management:

- **View configured servers** across all scopes (user, project, local)
- **Add new servers** with type, command, arguments, scope, and environment variables
- **Remove servers** directly from the UI
- **Check `.mcp.json`** files for additional server configs

---

### 📈 Usage & Costs Dashboard

Comprehensive analytics for your Claude Code usage:

- **Summary cards** — Total cost, session count, total tokens, total events
- **Token breakdown** — Input, output, cache read, cache write with visual bars
- **Per-session table** — Name, project, events, tokens in/out, cost, date
- **Time filters** — Today, This Week, This Month, All Time
- **Total row** — Aggregated totals for the selected period
- **Cost per session** shown in sidebar next to each session

---

### 🗂️ Additional Panels

| Panel | Description |
|-------|-------------|
| **File Changes** | Track all file modifications with type indicators (created/modified/deleted/renamed) |
| **Terminal Output** | Raw stdout/stderr/system logs with source filtering and search |
| **Diff View** | Side-by-side or unified diff visualization with line numbers |
| **Status Bar** | Model, tokens in/out, cache stats, cost, file changes, event count, project path |
| **Settings** | General, Models, Permissions, Memory, Advanced, About tabs |

---

## Architecture

Foundry follows a clean modular architecture with 9 distinct modules:

```
Sources/Foundry/
├── FoundryApp.swift                    # @main SwiftUI App entry point
│
├── Models/
│   ├── Session.swift                   # Session, TokenUsage, FileChange, DiffLine, LogEntry
│   ├── SessionEvent.swift              # Event types, metadata, stream JSON models, AnyCodable
│   └── ClaudeCommand.swift             # Slash command registry with categories
│
├── Services/
│   ├── ClaudeHistoryLoader.swift       # Discovers & parses all sessions from ~/.claude/
│   ├── ClaudeProcessController.swift   # Process spawning, stream-json I/O, lifecycle
│   ├── SessionManager.swift            # Multi-session state management (ObservableObject)
│   ├── EventParser.swift               # Stream-json line parser
│   ├── FileMonitor.swift               # DispatchSource-based file system watcher
│   ├── PersistenceManager.swift        # JSON persistence in Application Support
│   └── DiffEngine.swift                # LCS-based line diff + unified diff parser
│
└── Views/
    ├── MainView.swift                  # Root layout with NavigationSplitView
    ├── MarkdownView.swift              # Full Markdown renderer with code blocks
    ├── PromptView.swift                # Chat input with NSTextView (Enter to send)
    ├── CommandPaletteView.swift        # ⌘K command palette
    ├── OnboardingView.swift            # Claude not found error + install instructions
    ├── StatusBarView.swift             # Bottom status bar
    ├── SettingsView.swift              # Tabbed settings window
    ├── TerminalView.swift              # Raw log output with filtering
    ├── Sidebar/
    │   └── SidebarView.swift           # Session list with cost, status, search
    ├── Timeline/
    │   ├── TimelineView.swift          # Scrollable event timeline with filters
    │   └── TimelineEventView.swift     # Chat bubbles, tool cards, file pills
    └── Panels/
        ├── SkillsView.swift            # Skills browser with install
        ├── AgentsView.swift            # Agent viewer with custom agent creation
        ├── MCPView.swift               # MCP server manager
        ├── UsageView.swift             # Cost analytics dashboard
        └── DiffView.swift              # Unified/side-by-side diff viewer
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Swift Package Manager** | CLI-friendly builds without Xcode dependency |
| **ObservableObject** | Compatible with Swift 5 language mode for broad stability |
| **Process per message** | Uses `--resume` for multi-turn; avoids long-lived process issues |
| **JSONL scanning** | `~/.claude/projects/` is the source of truth, not `~/.claude/sessions/` |
| **Python dict parsing** | Claude Code stores messages as Python repr strings in JSONL |
| **NSTextView wrapper** | SwiftUI's TextEditor doesn't support Enter-to-send |
| **Custom Markdown parser** | Apple's `AttributedString(markdown:)` doesn't handle code blocks as views |
| **Hardened runtime** | Required for notarization; entitlements allow JIT and library loading |

---

## System Requirements

| Requirement | Minimum |
|-------------|---------|
| **macOS** | 14.0 (Sonoma) or later |
| **Architecture** | Apple Silicon (arm64) |
| **Claude Code** | Must be installed (`npm install -g @anthropic-ai/claude-code`) |
| **Disk Space** | ~10 MB |

---

## Installation

### Option 1: Download DMG (Recommended)

1. **[Download Foundry-1.0.0.dmg](Foundry-1.0.0.dmg)**
2. Open the DMG
3. Drag **Foundry** to **Applications**
4. Launch from Applications or Spotlight

> ✅ Apple Notarized — no Gatekeeper warnings  
> ✅ Code Signed with Developer ID  
> ✅ Hardened Runtime enabled

### Option 2: Build from Source

```bash
# Clone the repository
git clone <repo-url>
cd foundry

# Build (debug)
swift build

# Build (release)
swift build -c release

# Create .app bundle
./Scripts/build.sh

# Full release build with signing and notarization
./Scripts/build-release.sh
```

**Build Requirements:**
- Swift 6.0+ toolchain
- macOS 14.0+ SDK
- Command Line Tools (`xcode-select --install`)

---

## Usage

### First Launch

1. Foundry checks if Claude Code is installed
2. If not found, an onboarding screen shows installation instructions
3. If found, all existing Claude Code sessions are loaded automatically

### Browsing History

- All sessions from `~/.claude/projects/` appear in the sidebar
- Click any session to load its full conversation timeline
- Events are loaded lazily (only when selected) for performance
- Costs are shown next to each session

### Starting a New Session

1. Click **+** in the sidebar or `⌘N`
2. Select a project directory
3. Type a message and press **Enter**
4. Claude Code runs in the background and results stream into the timeline

### Using the Command Palette

1. Press `⌘K` to open the command palette
2. Type to search (e.g., "commit", "review", "model")
3. Press **Enter** to execute the selected command
4. The command is sent to the active Claude Code session

### Navigation Pages

Use the sidebar navigation to switch between:

| Page | Shortcut | Description |
|------|----------|-------------|
| **Sessions** | Default | Timeline, chat, file changes |
| **Skills** | — | Browse and install skills/plugins |
| **Agents** | — | View and add agents |
| **MCP Servers** | — | Manage MCP server connections |
| **Usage & Costs** | — | Analytics dashboard |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Enter` | Send message |
| `Shift+Enter` | New line in message |
| `⌘K` | Command palette |
| `⌘N` | New session |
| `⌘O` | Open project |
| `⌘.` | Stop active session |
| `⌘⇧R` | Restart session |
| `⌃⌘S` | Toggle sidebar |

---

## Configuration

### Settings

Access via **Foundry → Settings** or the gear icon:

| Tab | What it configures |
|-----|-------------------|
| **General** | Auto-save, raw output visibility, max log entries |
| **Models** | Default model selection (Opus / Sonnet / Haiku) |
| **Permissions** | Permission mode (default, acceptEdits, plan, auto) |
| **Memory** | Access Claude Code memory files in `~/.claude/` |
| **Advanced** | Claude Code path, version, health check, data management |
| **About** | Version info, credits |

---

## Data & Privacy

- Foundry **reads** Claude Code's data files — it does **not** modify them
- Session data is stored in `~/.claude/` (Claude Code's standard location)
- Foundry's own settings are in `~/Library/Application Support/Foundry/`
- No data is sent to external servers (beyond Claude Code's own API calls)
- All processing happens locally on your machine

---

## Technical Details

### How Session Discovery Works

```
~/.claude/
├── projects/
│   ├── -Users-you-Desktop-myproject/
│   │   ├── session-uuid-1.jsonl          ← Full conversation log
│   │   └── session-uuid-2.jsonl
│   └── -Users-you-Desktop-another/
│       └── session-uuid-3.jsonl
└── sessions/                              ← Only tracks running sessions (unreliable)
```

Foundry scans **all `.jsonl` files** across all project directories to discover every session. Each line in a JSONL file is a JSON object with fields like:

```json
{"type": "user", "message": {"role": "user", "content": "..."}, "timestamp": "2026-04-14T..."}
{"type": "assistant", "message": {"model": "claude-opus-4-6", "content": [...]}, "usage": {...}}
```

### How Claude Code Communication Works

```
┌──────────┐    stdin (prompt)     ┌──────────────┐
│  Foundry  │ ──────────────────→ │  claude -p    │
│  (SwiftUI)│ ←────────────────── │  --stream-json│
└──────────┘    stdout (events)    └──────────────┘
```

Each message spawns a new `claude` process with:
```bash
claude -p "<message>" --output-format stream-json --verbose --model <model> --resume <session-id>
```

The `--resume` flag maintains conversation continuity across process invocations.

---

## Project Stats

| Metric | Value |
|--------|-------|
| **Language** | Swift 6.3 |
| **Framework** | SwiftUI (100% native) |
| **Lines of Code** | 6,500+ |
| **Swift Files** | 27 |
| **Modules** | 9 (Models, Services × 7, Views) |
| **Build System** | Swift Package Manager |
| **Binary Size** | ~3.5 MB (release, arm64) |
| **DMG Size** | 2.5 MB |
| **Min macOS** | 14.0 (Sonoma) |
| **Signing** | Developer ID + Hardened Runtime |
| **Notarization** | Apple Notarized + Stapled |

---

## Development

### Project Structure

```
foundry/
├── Package.swift                      # SPM package definition
├── Sources/Foundry/                   # All source code
├── Resources/                         # Logo SVG, PNG, .icns
├── Scripts/
│   ├── build.sh                       # Quick debug/release build
│   └── build-release.sh               # Full: build + sign + DMG + notarize
├── Foundry.app/                       # Built app bundle
├── Foundry-1.0.0.dmg                  # Distribution DMG
└── Foundry.entitlements               # Hardened runtime entitlements
```

### Quick Development Cycle

```bash
# Build and run
swift build && .build/debug/Foundry

# Build release
./Scripts/build.sh
open Foundry.app

# Full release with notarization
./Scripts/build-release.sh
```

---

## Roadmap

- [ ] Real-time streaming (partial message rendering as they arrive)
- [ ] File diff visualization with accept/reject actions
- [ ] Session search across all history
- [ ] Export session as Markdown
- [ ] Custom themes and color schemes
- [ ] Plugin marketplace integration
- [ ] Session tagging and organization
- [ ] Git integration (branch awareness, commit history)
- [ ] Multiple windows support
- [ ] Touch Bar support

---

## Credits

**Foundry** is built and maintained by **[WorthDoing AI](https://worthdoing.ai)**.

Built entirely using **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** by Anthropic — the very tool Foundry was designed to interface with.

---

<p align="center">
  <img src="https://raw.githubusercontent.com/Worth-Doing/brand-assets/main/png/variants/04-horizontal.png" alt="WorthDoing.ai" width="400" />
</p>

<p align="center">
  <sub>© 2026 WorthDoing AI. All rights reserved.</sub>
</p>

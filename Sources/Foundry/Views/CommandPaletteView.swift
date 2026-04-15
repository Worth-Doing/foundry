import SwiftUI

// MARK: - Palette Item types

enum PaletteItemKind {
    case command(ClaudeCommand)
    case session(Session)
    case project(String)
    case searchAction(String)
    case action(String, String, () -> Void) // id, label, action
}

struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let kind: PaletteItemKind
    var isEnabled: Bool = true
}

// MARK: - Command Palette View

struct CommandPaletteView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var mode: PaletteMode = .commands
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    enum PaletteMode: String, CaseIterable {
        case commands = "Commands"
        case sessions = "Sessions"
        case projects = "Projects"
        case search = "Search"
    }

    // MARK: - Items

    private var items: [PaletteItem] {
        switch mode {
        case .commands:
            return commandItems
        case .sessions:
            return sessionItems
        case .projects:
            return projectItems
        case .search:
            return searchItems
        }
    }

    private var commandItems: [PaletteItem] {
        let commands = ClaudeCommandRegistry.search(searchText)
        let hasSession = sessionManager.activeSessionID != nil

        // Add built-in palette actions at the top
        var items: [PaletteItem] = []

        if searchText.isEmpty {
            items.append(PaletteItem(
                id: "_switch_sessions",
                icon: "bubble.left.and.bubble.right",
                title: "Switch Session...",
                subtitle: "Jump to another session",
                badge: nil,
                kind: .action("_switch_sessions", "Switch Session") { [self] in
                    mode = .sessions
                    searchText = ""
                }
            ))
            items.append(PaletteItem(
                id: "_open_project",
                icon: "folder.badge.plus",
                title: "Open Project...",
                subtitle: "Start a new session in a project",
                badge: nil,
                kind: .action("_open_project", "Open Project") {
                    mode = .projects
                    searchText = ""
                }
            ))
            items.append(PaletteItem(
                id: "_search_all",
                icon: "magnifyingglass",
                title: "Search Everything...",
                subtitle: "Search across all sessions",
                badge: nil,
                kind: .action("_search_all", "Search") { [self] in
                    mode = .search
                    searchText = ""
                }
            ))
        }

        // Claude commands
        for cmd in commands {
            items.append(PaletteItem(
                id: cmd.id,
                icon: cmd.icon,
                title: cmd.displayName,
                subtitle: cmd.description,
                badge: cmd.name,
                kind: .command(cmd),
                isEnabled: !cmd.requiresSession || hasSession
            ))
        }

        return items
    }

    private var sessionItems: [PaletteItem] {
        let q = searchText.lowercased()
        let sessions = q.isEmpty ? sessionManager.sessions : sessionManager.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.projectPath.localizedCaseInsensitiveContains(q)
        }

        return sessions.map { session in
            PaletteItem(
                id: session.id.uuidString,
                icon: session.status == .running ? "circle.fill" : "bubble.left",
                title: session.name,
                subtitle: Utilities.abbreviatePath(session.projectPath),
                badge: Utilities.displayModelName(session.modelName),
                kind: .session(session)
            )
        }
    }

    private var projectItems: [PaletteItem] {
        let q = searchText.lowercased()
        let projects = sessionManager.recentProjects

        var items: [PaletteItem] = []

        // "Open new" always at top
        items.append(PaletteItem(
            id: "_browse_project",
            icon: "folder.badge.plus",
            title: "Browse for Project...",
            subtitle: "Open a new project from Finder",
            badge: nil,
            kind: .action("_browse", "Browse") { }
        ))

        // Recent projects
        for path in projects {
            if !q.isEmpty && !path.localizedCaseInsensitiveContains(q) { continue }
            items.append(PaletteItem(
                id: "project_\(path)",
                icon: "folder.fill",
                title: URL(fileURLWithPath: path).lastPathComponent,
                subtitle: Utilities.abbreviatePath(path),
                badge: nil,
                kind: .project(path)
            ))
        }

        return items
    }

    private var searchItems: [PaletteItem] {
        guard !searchText.isEmpty else {
            return [PaletteItem(
                id: "_search_hint",
                icon: "magnifyingglass",
                title: "Type to search...",
                subtitle: "Search sessions, messages, file changes",
                badge: nil,
                kind: .action("_hint", "", { }),
                isEnabled: false
            )]
        }

        let results = sessionManager.searchSessions(query: searchText)
        return results.prefix(20).map { result in
            PaletteItem(
                id: result.id.uuidString,
                icon: searchMatchIcon(result.matchType),
                title: result.sessionName,
                subtitle: result.preview,
                badge: result.matchType.rawValue,
                kind: .searchAction(result.sessionID.uuidString)
            )
        }
    }

    private func searchMatchIcon(_ type: SearchMatchType) -> String {
        switch type {
        case .sessionName: return "text.bubble"
        case .projectPath: return "folder"
        case .userMessage: return "person"
        case .assistantMessage: return "bubble.left"
        case .fileChange: return "doc"
        case .sessionNotes: return "note.text"
        case .tag: return "tag"
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                if mode != .commands {
                    Button {
                        withAnimation(FoundryAnimation.snappy) {
                            mode = .commands
                            searchText = ""
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(.caption, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                TextField(placeholderText, text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.title3))
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelected()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button("ESC") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(16)

            Divider()

            // Items list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if mode == .commands && searchText.isEmpty {
                        // Show mode sections for commands
                        let paletteActions = items.filter {
                            if case .action = $0.kind { return true }
                            return false
                        }
                        let commandList = items.filter {
                            if case .command = $0.kind { return true }
                            return false
                        }

                        if !paletteActions.isEmpty {
                            Section {
                                ForEach(paletteActions) { item in
                                    PaletteRow(item: item, isSelected: isItemSelected(item)) {
                                        executeItem(item)
                                    }
                                }
                            } header: {
                                sectionHeader("Quick Actions")
                            }
                        }

                        // Group commands by category
                        let grouped = Dictionary(grouping: commandList) { item -> String in
                            if case .command(let cmd) = item.kind {
                                return cmd.category.rawValue
                            }
                            return ""
                        }
                        let sortedKeys = ClaudeCommand.CommandCategory.allCases.map(\.rawValue)
                        ForEach(sortedKeys, id: \.self) { key in
                            if let groupItems = grouped[key], !groupItems.isEmpty {
                                Section {
                                    ForEach(groupItems) { item in
                                        PaletteRow(item: item, isSelected: isItemSelected(item)) {
                                            executeItem(item)
                                        }
                                    }
                                } header: {
                                    sectionHeader(key)
                                }
                            }
                        }
                    } else {
                        // Flat list for other modes
                        ForEach(items) { item in
                            PaletteRow(item: item, isSelected: isItemSelected(item)) {
                                executeItem(item)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer
            HStack(spacing: Spacing.lg) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9))
                    Text("Navigate")
                }
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "return")
                        .font(.system(size: 9))
                    Text("Execute")
                }
                HStack(spacing: Spacing.xs) {
                    Text("esc")
                        .font(.system(.caption2, design: .monospaced))
                    Text("Close")
                }

                Spacer()

                // Mode tabs
                ForEach(PaletteMode.allCases, id: \.self) { m in
                    Button {
                        withAnimation(FoundryAnimation.snappy) {
                            mode = m
                            searchText = ""
                            selectedIndex = 0
                        }
                    } label: {
                        Text(m.rawValue)
                            .font(.caption2)
                            .foregroundStyle(mode == m ? .primary : .tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(mode == m ? Color.accentColor.opacity(0.1) : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(colorScheme == .light ? 0.1 : 0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private var placeholderText: String {
        switch mode {
        case .commands: return "Search commands..."
        case .sessions: return "Search sessions..."
        case .projects: return "Search projects..."
        case .search: return "Search everything..."
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func isItemSelected(_ item: PaletteItem) -> Bool {
        let allItems = items
        guard selectedIndex < allItems.count else { return false }
        return allItems[selectedIndex].id == item.id
    }

    private func executeSelected() {
        let allItems = items
        guard selectedIndex < allItems.count else { return }
        executeItem(allItems[selectedIndex])
    }

    private func executeItem(_ item: PaletteItem) {
        guard item.isEnabled else { return }

        switch item.kind {
        case .command(let cmd):
            if cmd.requiresSession {
                guard let sessionID = sessionManager.activeSessionID else { return }
                sessionManager.sendCommand(to: sessionID, command: cmd)
            } else {
                executeSystemCommand(cmd)
            }
            isPresented = false

        case .session(let session):
            sessionManager.switchToSession(session.id)
            isPresented = false

        case .project(let path):
            let id = sessionManager.createSession(projectPath: path)
            sessionManager.startSession(id)
            isPresented = false

        case .searchAction(let sessionIDString):
            if let uuid = UUID(uuidString: sessionIDString) {
                sessionManager.switchToSession(uuid)
            }
            isPresented = false

        case .action(let id, _, let action):
            if id == "_browse" {
                if let url = Utilities.showOpenProjectPanel() {
                    let sid = sessionManager.createSession(projectPath: url.path)
                    sessionManager.startSession(sid)
                    isPresented = false
                }
            } else {
                action()
            }
        }
    }

    private func executeSystemCommand(_ command: ClaudeCommand) {
        switch command.id {
        case "config":
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case "doctor":
            runClaudeCommand(["doctor"])
        case "help":
            if let url = URL(string: "https://docs.anthropic.com/en/docs/claude-code") {
                NSWorkspace.shared.open(url)
            }
        case "bug":
            if let url = URL(string: "https://github.com/anthropics/claude-code/issues") {
                NSWorkspace.shared.open(url)
            }
        case "login", "logout":
            runClaudeCommand([command.id])
        default:
            if let sessionID = sessionManager.activeSessionID {
                sessionManager.sendCommand(to: sessionID, command: command)
            }
        }
    }

    private func runClaudeCommand(_ args: [String]) {
        let env = ShellEnvironmentResolver.shared.resolvedEnvironment()
        guard let path = ClaudeProcessController.findClaudePath(environment: env) else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    if let sessionID = sessionManager.activeSessionID,
                       let index = sessionManager.sessions.firstIndex(where: { $0.id == sessionID }) {
                        sessionManager.sessions[index].events.append(
                            SessionEvent(type: .systemInfo, content: output)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Palette Row

struct PaletteRow: View {
    let item: PaletteItem
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .frame(width: 24)
                    .foregroundStyle(item.isEnabled ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badge = item.badge {
                    Text(badge)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                                .fill(Color.accentColor.opacity(colorScheme == .light ? 0.06 : 0.1))
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.5)
    }
}

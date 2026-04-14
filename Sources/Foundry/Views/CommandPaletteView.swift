import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredCommands: [ClaudeCommand] {
        ClaudeCommandRegistry.search(searchText)
    }

    private var groupedCommands: [(ClaudeCommand.CommandCategory, [ClaudeCommand])] {
        let commands = filteredCommands
        return ClaudeCommand.CommandCategory.allCases.compactMap { category in
            let cmds = commands.filter { $0.category == category }
            return cmds.isEmpty ? nil : (category, cmds)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search commands...", text: $searchText)
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
                .font(.caption)
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(16)

            Divider()

            // Commands list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groupedCommands, id: \.0) { category, commands in
                        Section {
                            ForEach(commands) { command in
                                CommandRow(
                                    command: command,
                                    isSelected: isCommandSelected(command),
                                    hasActiveSession: sessionManager.activeSessionID != nil
                                ) {
                                    execute(command)
                                }
                            }
                        } header: {
                            Text(category.rawValue)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 400)

            Divider()

            // Footer
            HStack {
                Text("↑↓ Navigate")
                Text("↵ Execute")
                Text("esc Close")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(8)
        }
        .frame(width: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 20)
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private func isCommandSelected(_ command: ClaudeCommand) -> Bool {
        let flatCommands = filteredCommands
        guard selectedIndex < flatCommands.count else { return false }
        return flatCommands[selectedIndex].id == command.id
    }

    private func executeSelected() {
        let commands = filteredCommands
        guard selectedIndex < commands.count else { return }
        execute(commands[selectedIndex])
    }

    private func execute(_ command: ClaudeCommand) {
        if command.requiresSession {
            guard let sessionID = sessionManager.activeSessionID else { return }
            sessionManager.sendCommand(to: sessionID, command: command)
        } else {
            executeSystemCommand(command)
        }
        isPresented = false
    }

    private func executeSystemCommand(_ command: ClaudeCommand) {
        switch command.id {
        case "config":
            // Open settings window
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
            // For other commands, send through active session if available
            if let sessionID = sessionManager.activeSessionID {
                sessionManager.sendCommand(to: sessionID, command: command)
            }
        }
    }

    private func runClaudeCommand(_ args: [String]) {
        guard let path = ClaudeProcessController.findClaudePath() else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args

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

struct CommandRow: View {
    let command: ClaudeCommand
    let isSelected: Bool
    let hasActiveSession: Bool
    let action: () -> Void

    private var isEnabled: Bool {
        !command.requiresSession || hasActiveSession
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: command.icon)
                    .frame(width: 24)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.displayName)
                        .font(.system(.body, weight: .medium))

                    Text(command.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(command.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

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
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
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
                                .font(.system(.caption2, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.top, 10)
                                .padding(.bottom, 2)
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
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .frame(width: 520)
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
    @Environment(\.colorScheme) private var colorScheme

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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

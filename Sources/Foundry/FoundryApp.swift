import SwiftUI

@main
struct FoundryApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var appSettings = AppSettings()
    @State private var showCommandPalette = false

    var body: some Scene {
        WindowGroup {
            MainView(showCommandPalette: $showCommandPalette)
                .environmentObject(sessionManager)
                .environmentObject(appSettings)
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(appSettings.resolvedColorScheme)
                .onAppear {
                    sessionManager.appSettings = appSettings
                    sessionManager.checkClaudeAvailability()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1400, height: 900)
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("New Session...") {
                    showNewSessionDialog()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Open Project...") {
                    showNewSessionDialog()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Close Session") {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.stopSession(id)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command])
                .disabled(sessionManager.activeSessionID == nil)
            }

            // Session menu
            CommandMenu("Session") {
                Button("Send Message") {}
                    .keyboardShortcut(.return, modifiers: [.command])

                Divider()

                Button("Stop Session") {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.stopSession(id)
                    }
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(sessionManager.activeSession?.status != .running)

                Button("Restart Session") {
                    restartActiveSession()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(sessionManager.activeSessionID == nil)

                Divider()

                Button("Previous Session") {
                    navigateSession(direction: -1)
                }
                .keyboardShortcut("[", modifiers: [.command])

                Button("Next Session") {
                    navigateSession(direction: 1)
                }
                .keyboardShortcut("]", modifiers: [.command])

                Divider()

                Button("Pin/Unpin Session") {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.togglePin(id)
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(sessionManager.activeSessionID == nil)

                Button("Favorite/Unfavorite Session") {
                    if let id = sessionManager.activeSessionID {
                        sessionManager.toggleFavorite(id)
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(sessionManager.activeSessionID == nil)

                Divider()

                Button("Clear Conversation") {
                    if let id = sessionManager.activeSessionID {
                        let cmd = ClaudeCommandRegistry.allCommands.first { $0.id == "clear" }!
                        sessionManager.sendCommand(to: id, command: cmd)
                    }
                }
                .disabled(sessionManager.activeSessionID == nil)

                Button("Copy Last Response") {
                    copyLastResponse()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(sessionManager.activeSessionID == nil)
            }

            // Command palette
            CommandMenu("Commands") {
                Button("Command Palette...") {
                    showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                ForEach(ClaudeCommandRegistry.allCommands.prefix(10), id: \.id) { command in
                    Button(command.displayName) {
                        executeCommand(command)
                    }
                }
            }

            // Navigate menu
            CommandMenu("Navigate") {
                Button("Sessions") {
                    NotificationCenter.default.post(name: .navigateToPage, object: NavigationPage.sessions)
                }
                .keyboardShortcut("1", modifiers: [.command])

                Button("Skills") {
                    NotificationCenter.default.post(name: .navigateToPage, object: NavigationPage.skills)
                }
                .keyboardShortcut("2", modifiers: [.command])

                Button("Agents") {
                    NotificationCenter.default.post(name: .navigateToPage, object: NavigationPage.agents)
                }
                .keyboardShortcut("3", modifiers: [.command])

                Button("MCP Servers") {
                    NotificationCenter.default.post(name: .navigateToPage, object: NavigationPage.mcp)
                }
                .keyboardShortcut("4", modifiers: [.command])

                Button("Usage & Costs") {
                    NotificationCenter.default.post(name: .navigateToPage, object: NavigationPage.usage)
                }
                .keyboardShortcut("5", modifiers: [.command])
            }

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()

                Button("Toggle Terminal Panel") {
                    appSettings.showTerminalPanel.toggle()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle File Panel") {
                    appSettings.showFilePanel.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Button("Reload Sessions") {
                    sessionManager.loadClaudeHistory()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(sessionManager)
                .environmentObject(appSettings)
                .preferredColorScheme(appSettings.resolvedColorScheme)
        }
    }

    private func showNewSessionDialog() {
        if let url = Utilities.showOpenProjectPanel(message: "Select a project directory for the new session") {
            let sessionID = sessionManager.createSession(
                projectPath: url.path,
                model: appSettings.defaultModel
            )
            sessionManager.startSession(sessionID)
        }
    }

    private func restartActiveSession() {
        guard let id = sessionManager.activeSessionID else { return }
        sessionManager.stopSession(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            sessionManager.startSession(id)
        }
    }

    private func executeCommand(_ command: ClaudeCommand) {
        guard let id = sessionManager.activeSessionID else { return }
        sessionManager.sendCommand(to: id, command: command)
    }

    private func navigateSession(direction: Int) {
        guard let currentID = sessionManager.activeSessionID,
              let currentIdx = sessionManager.sessions.firstIndex(where: { $0.id == currentID }) else {
            // No active session — select the first one
            if let first = sessionManager.sessions.first {
                sessionManager.switchToSession(first.id)
            }
            return
        }

        let newIdx = currentIdx + direction
        guard newIdx >= 0, newIdx < sessionManager.sessions.count else { return }
        sessionManager.switchToSession(sessionManager.sessions[newIdx].id)
    }

    private func copyLastResponse() {
        guard let session = sessionManager.activeSession else { return }
        if let lastResponse = session.events.last(where: { $0.type == .assistantMessage }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lastResponse.content, forType: .string)
        }
    }
}

// MARK: - Navigation Notification

extension Notification.Name {
    static let navigateToPage = Notification.Name("navigateToPage")
}

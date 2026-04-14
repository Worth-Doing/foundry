import SwiftUI

@main
struct FoundryApp: App {
    @StateObject private var sessionManager = SessionManager()
    @State private var showCommandPalette = false

    var body: some Scene {
        WindowGroup {
            MainView(showCommandPalette: $showCommandPalette)
                .environmentObject(sessionManager)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
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
                    showOpenProjectDialog()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            // Edit menu additions
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

                Button("Restart Session") {
                    restartActiveSession()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
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

            // View menu
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(sessionManager)
        }
    }

    private func showNewSessionDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory for the new session"

        if panel.runModal() == .OK, let url = panel.url {
            let sessionID = sessionManager.createSession(projectPath: url.path)
            sessionManager.startSession(sessionID)
        }
    }

    private func showOpenProjectDialog() {
        showNewSessionDialog()
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
}

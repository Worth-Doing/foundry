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

                Button("Clear Conversation") {
                    if let id = sessionManager.activeSessionID {
                        let cmd = ClaudeCommandRegistry.allCommands.first { $0.id == "clear" }!
                        sessionManager.sendCommand(to: id, command: cmd)
                    }
                }
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project directory for the new session"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
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
}

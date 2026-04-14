import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedTab = SettingsTab.general
    @State private var defaultModel = "claude-sonnet-4-6"
    @State private var autoSaveSessions = true
    @State private var maxLogEntries = 10000
    @State private var showRawOutput = false
    @State private var permissionMode = "default"

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case models = "Models"
        case permissions = "Permissions"
        case memory = "Memory"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            modelsTab
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(SettingsTab.models)

            permissionsTab
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)

            memoryTab
                .tabItem { Label("Memory", systemImage: "brain") }
                .tag(SettingsTab.memory)

            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)

            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 550, height: 400)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Sessions") {
                Toggle("Auto-save sessions", isOn: $autoSaveSessions)
                Toggle("Show raw output by default", isOn: $showRawOutput)

                Stepper("Max log entries: \(maxLogEntries)",
                        value: $maxLogEntries, in: 1000...100000, step: 1000)
            }

            Section("Appearance") {
                Picker("Color Scheme", selection: .constant("System")) {
                    Text("System").tag("System")
                    Text("Light").tag("Light")
                    Text("Dark").tag("Dark")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        Form {
            Section("Default Model") {
                Picker("Model", selection: $defaultModel) {
                    Text("Claude Opus 4.6").tag("claude-opus-4-6")
                    Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                    Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }

                Text("The model used for new sessions. Can be changed per-session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model Info") {
                LabeledContent("Opus 4.6", value: "Most capable, highest quality")
                LabeledContent("Sonnet 4.6", value: "Balanced performance")
                LabeledContent("Haiku 4.5", value: "Fastest, most efficient")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section("Permission Mode") {
                Picker("Mode", selection: $permissionMode) {
                    Text("Default").tag("default")
                    Text("Accept Edits").tag("acceptEdits")
                    Text("Plan").tag("plan")
                    Text("Auto").tag("auto")
                }

                Text("Controls how Claude handles permission requests for tool use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tool Permissions") {
                LabeledContent("Bash") {
                    Text("Prompt")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
                LabeledContent("Edit") {
                    Text("Allow")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
                LabeledContent("Read") {
                    Text("Allow")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
                LabeledContent("Write") {
                    Text("Allow")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code Memory")
                .font(.headline)

            Text("Memory files stored in ~/.claude/ help Claude remember context across sessions.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Memory Directory") {
                if let home = ProcessInfo.processInfo.environment["HOME"] {
                    let path = "\(home)/.claude"
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            }

            Button("Run /memory in Active Session") {
                if let sessionID = sessionManager.activeSessionID {
                    let memoryCmd = ClaudeCommandRegistry.allCommands.first { $0.id == "memory" }!
                    sessionManager.sendCommand(to: sessionID, command: memoryCmd)
                }
            }
            .disabled(sessionManager.activeSessionID == nil)

            Spacer()
        }
        .padding()
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        Form {
            Section("Claude Code") {
                if let path = sessionManager.claudePath {
                    LabeledContent("Path", value: path)
                }
                if let version = sessionManager.claudeVersion {
                    LabeledContent("Version", value: version)
                }

                Button("Run Health Check (/doctor)") {
                    // Run claude doctor
                    if let path = ClaudeProcessController.findClaudePath() {
                        DispatchQueue.global().async {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: path)
                            process.arguments = ["doctor"]
                            try? process.run()
                            process.waitUntilExit()
                        }
                    }
                }
            }

            Section("Data") {
                Button("Open App Support Directory") {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let foundryDir = appSupport.appendingPathComponent("Foundry")
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: foundryDir.path)
                }

                Button("Clear All Sessions", role: .destructive) {
                    for session in sessionManager.sessions {
                        sessionManager.deleteSession(session.id)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "hammer.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Foundry")
                .font(.title.bold())

            Text("Native Claude Code Interface for macOS")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Built with SwiftUI")
                Text("Powered by Claude Code")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

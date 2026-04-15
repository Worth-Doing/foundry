import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedTab = SettingsTab.general

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
        .frame(width: 560, height: 420)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Sessions") {
                Toggle("Auto-save sessions", isOn: $appSettings.autoSaveSessions)
                Toggle("Show raw output by default", isOn: $appSettings.showRawOutput)

                Stepper("Max log entries: \(appSettings.maxLogEntries)",
                        value: $appSettings.maxLogEntries, in: 1000...100000, step: 1000)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appSettings.colorScheme) {
                    ForEach(AppSettings.AppColorScheme.allCases, id: \.self) { scheme in
                        Label(scheme.rawValue, systemImage: scheme.icon)
                            .tag(scheme)
                    }
                }

                Toggle("Show Terminal Panel", isOn: $appSettings.showTerminalPanel)
                Toggle("Show File Changes Panel", isOn: $appSettings.showFilePanel)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Models Tab

    private var modelsTab: some View {
        Form {
            Section("Default Model") {
                Picker("Model", selection: $appSettings.defaultModel) {
                    Text("Claude Opus 4.6").tag("claude-opus-4-6")
                    Text("Claude Sonnet 4.6").tag("claude-sonnet-4-6")
                    Text("Claude Haiku 4.5").tag("claude-haiku-4-5-20251001")
                }

                Text("The model used for new sessions. Can be changed per-session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model Capabilities") {
                modelInfoRow(
                    name: "Opus 4.6",
                    badge: "Most Capable",
                    badgeColor: .purple,
                    description: "Highest quality reasoning, best for complex tasks"
                )
                modelInfoRow(
                    name: "Sonnet 4.6",
                    badge: "Balanced",
                    badgeColor: .blue,
                    description: "Great balance of speed and capability"
                )
                modelInfoRow(
                    name: "Haiku 4.5",
                    badge: "Fastest",
                    badgeColor: .green,
                    description: "Most efficient for simple tasks"
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func modelInfoRow(name: String, badge: String, badgeColor: Color, description: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(.body, weight: .medium))
                    Text(badge)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(badgeColor)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Permissions Tab

    private var permissionsTab: some View {
        Form {
            Section("Permission Mode") {
                Picker("Mode", selection: $appSettings.permissionMode) {
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
                permissionRow(tool: "Bash", status: "Prompt", color: .orange)
                permissionRow(tool: "Edit", status: "Allow", color: .green)
                permissionRow(tool: "Read", status: "Allow", color: .green)
                permissionRow(tool: "Write", status: "Allow", color: .green)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func permissionRow(tool: String, status: String, color: Color) -> some View {
        LabeledContent(tool) {
            Text(status)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(color)
        }
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude Code Memory")
                .font(.headline)

            Text("Memory files stored in ~/.claude/ help Claude remember context across sessions.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    if let home = ProcessInfo.processInfo.environment["HOME"] {
                        let path = "\(home)/.claude"
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                    }
                } label: {
                    Label("Open Memory Directory", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    if let sessionID = sessionManager.activeSessionID {
                        let memoryCmd = ClaudeCommandRegistry.allCommands.first { $0.id == "memory" }!
                        sessionManager.sendCommand(to: sessionID, command: memoryCmd)
                    }
                } label: {
                    Label("Run /memory in Active Session", systemImage: "brain")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(sessionManager.activeSessionID == nil)
            }

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

                Button("Reset All Settings") {
                    let domain = Bundle.main.bundleIdentifier ?? "com.foundry.app"
                    UserDefaults.standard.removePersistentDomain(forName: domain)
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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "hammer.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Foundry")
                    .font(.title.bold())

                Text("Native Claude Code Interface for macOS")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Version 2.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: Capsule())

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

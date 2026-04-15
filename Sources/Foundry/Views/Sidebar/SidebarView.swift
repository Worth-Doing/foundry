import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appSettings: AppSettings
    @State private var searchText = ""
    @State private var renamingSessionID: UUID?
    @State private var renameText = ""

    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessionManager.sessions
        }
        return sessionManager.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.projectPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var activeSessions: [Session] {
        filteredSessions.filter { $0.status == .running || $0.status == .idle || $0.status == .initializing }
    }

    var historySessions: [Session] {
        filteredSessions.filter { $0.status == .stopped || $0.status == .error }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { sessionManager.activeSessionID },
                set: { id in
                    if let id = id {
                        sessionManager.switchToSession(id)
                    }
                }
            )) {
                if !activeSessions.isEmpty {
                    Section("Active") {
                        ForEach(activeSessions) { session in
                            SessionRow(session: session)
                                .tag(session.id)
                                .contextMenu { sessionContextMenu(session) }
                        }
                    }
                }

                Section("History (\(historySessions.count))") {
                    if sessionManager.isLoadingHistory {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading sessions...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    ForEach(historySessions) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu { sessionContextMenu(session) }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Filter sessions")

            Divider()

            // Bottom bar
            HStack(spacing: 12) {
                Button {
                    openNewSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Session (Cmd+N)")

                Button {
                    sessionManager.loadClaudeHistory()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Reload Claude Code sessions")

                Spacer()

                if let version = sessionManager.claudeVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .navigationTitle("Foundry")
    }

    private func openNewSession() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select project directory"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            let id = sessionManager.createSession(
                projectPath: url.path,
                model: appSettings.defaultModel
            )
            sessionManager.startSession(id)
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        if session.status == .running || session.status == .idle {
            Button("Stop Session") {
                sessionManager.stopSession(session.id)
            }
        }

        if session.status == .stopped || session.status == .error {
            Button("Resume Session") {
                sessionManager.startSession(session.id)
            }
        }

        Divider()

        Button("Rename...") {
            renamingSessionID = session.id
            renameText = session.name
        }

        Button("Duplicate Session") {
            let id = sessionManager.createSession(
                projectPath: session.projectPath,
                name: session.name + " (copy)",
                model: session.modelName
            )
            sessionManager.startSession(id)
        }

        Divider()

        Button("Copy Project Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.projectPath, forType: .string)
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.projectPath)
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            sessionManager.deleteSession(session.id)
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 24, height: 24)

                if session.status == .running {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    // Model badge
                    Text(shortModelName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(modelColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(modelColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))

                    Text(abbreviatedPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if session.tokenUsage.estimatedCostUSD > 0 {
                    Text(String(format: "$%.2f", session.tokenUsage.estimatedCostUSD))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(session.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle: return .blue
        case .initializing: return .orange
        case .error: return .red
        case .stopped: return .secondary
        }
    }

    private var shortModelName: String {
        let name = session.modelName
        if name.contains("opus") { return "Opus" }
        if name.contains("haiku") { return "Haiku" }
        return "Sonnet"
    }

    private var modelColor: Color {
        let name = session.modelName
        if name.contains("opus") { return .purple }
        if name.contains("haiku") { return .green }
        return .blue
    }

    private var abbreviatedPath: String {
        let path = session.projectPath
        if let home = ProcessInfo.processInfo.environment["HOME"],
           path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

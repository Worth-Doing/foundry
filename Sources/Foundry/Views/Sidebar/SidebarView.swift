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
            HStack(spacing: Spacing.md) {
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
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Foundry")
    }

    private func openNewSession() {
        if let url = Utilities.showOpenProjectPanel(message: "Select project directory") {
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
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 24, height: 24)
                    .scaleEffect(session.status == .running && isPulsing ? 1.2 : 1.0)
                    .opacity(session.status == .running && isPulsing ? 0.5 : 1.0)
                    .animation(
                        session.status == .running
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )

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
            .onAppear {
                if session.status == .running { isPulsing = true }
            }
            .onChange(of: session.status) { _, newStatus in
                isPulsing = newStatus == .running
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
        Utilities.statusColor(for: session.status)
    }

    private var shortModelName: String {
        Utilities.displayModelName(session.modelName)
    }

    private var modelColor: Color {
        Utilities.modelColor(session.modelName)
    }

    private var abbreviatedPath: String {
        Utilities.abbreviatePath(session.projectPath)
    }
}

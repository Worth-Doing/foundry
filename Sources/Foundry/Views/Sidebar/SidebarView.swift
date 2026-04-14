import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showNewSession = false
    @State private var searchText = ""

    var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessionManager.sessions
        }
        return sessionManager.sessions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.projectPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Session list
            List(selection: Binding(
                get: { sessionManager.activeSessionID },
                set: { id in
                    if let id = id {
                        sessionManager.switchToSession(id)
                    }
                }
            )) {
                Section("Active Sessions") {
                    ForEach(filteredSessions.filter { $0.status == .running || $0.status == .idle }) { session in
                        SessionRow(session: session)
                            .tag(session.id)
                            .contextMenu {
                                sessionContextMenu(session)
                            }
                    }
                }

                if filteredSessions.contains(where: { $0.status == .stopped || $0.status == .error }) {
                    Section("Previous Sessions") {
                        ForEach(filteredSessions.filter { $0.status == .stopped || $0.status == .error }) { session in
                            SessionRow(session: session)
                                .tag(session.id)
                                .contextMenu {
                                    sessionContextMenu(session)
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Filter sessions")

            Divider()

            // Bottom actions
            HStack(spacing: 12) {
                Button {
                    openNewSession()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Session")

                Spacer()

                if let version = sessionManager.claudeVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
        }
        .navigationTitle("Foundry")
    }

    private func openNewSession() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select project directory"

        if panel.runModal() == .OK, let url = panel.url {
            let id = sessionManager.createSession(projectPath: url.path)
            sessionManager.startSession(id)
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        if session.status == .running {
            Button("Stop Session") {
                sessionManager.stopSession(session.id)
            }
        }

        if session.status == .stopped || session.status == .error {
            Button("Restart Session") {
                sessionManager.startSession(session.id)
            }
        }

        Divider()

        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.projectPath)
        }

        Divider()

        Button("Delete Session", role: .destructive) {
            sessionManager.deleteSession(session.id)
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            if session.status == .running {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
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
        case .stopped: return .gray
        }
    }

    private var abbreviatedPath: String {
        let path = session.projectPath
        if let homeDir = ProcessInfo.processInfo.environment["HOME"],
           path.hasPrefix(homeDir) {
            return "~" + path.dropFirst(homeDir.count)
        }
        return path
    }
}

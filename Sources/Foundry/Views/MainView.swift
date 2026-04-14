import SwiftUI

struct MainView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var showCommandPalette: Bool
    @State private var showTerminalPanel = true
    @State private var showFilePanel = false
    @State private var sidebarWidth: CGFloat = 240
    @State private var terminalHeight: CGFloat = 180
    @State private var filePanelWidth: CGFloat = 320

    var body: some View {
        Group {
            if !sessionManager.claudeAvailable {
                OnboardingView()
            } else {
                mainLayout
            }
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView(isPresented: $showCommandPalette)
                .environmentObject(sessionManager)
        }
    }

    @ViewBuilder
    private var mainLayout: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 200)
        } detail: {
            if let session = sessionManager.activeSession {
                sessionDetailView(session)
            } else {
                WelcomeView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
    }

    @ViewBuilder
    private func sessionDetailView(_ session: Session) -> some View {
        VStack(spacing: 0) {
            // Main content area
            HSplitView {
                // Center: Timeline + Prompt
                VStack(spacing: 0) {
                    TimelineView(session: session)

                    Divider()

                    PromptView(sessionID: session.id)
                        .frame(minHeight: 60, maxHeight: 150)
                }
                .frame(minWidth: 400)

                // Right: File changes panel
                if showFilePanel {
                    VStack(spacing: 0) {
                        filePanelHeader
                        Divider()
                        FileChangesPanel(session: session)
                    }
                    .frame(width: filePanelWidth)
                }
            }

            // Bottom: Terminal logs
            if showTerminalPanel {
                Divider()
                VStack(spacing: 0) {
                    terminalPanelHeader
                    TerminalView(session: session)
                }
                .frame(height: terminalHeight)
            }

            // Status bar
            StatusBarView(session: session)
        }
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            showCommandPalette = true
        } label: {
            Image(systemName: "command")
        }
        .help("Command Palette (⌘K)")

        Toggle(isOn: $showFilePanel) {
            Image(systemName: "doc.on.doc")
        }
        .help("Toggle File Changes Panel")

        Toggle(isOn: $showTerminalPanel) {
            Image(systemName: "terminal")
        }
        .help("Toggle Terminal Panel")

        if let id = sessionManager.activeSessionID,
           sessionManager.activeSession?.status == .running {
            Button {
                sessionManager.stopSession(id)
            } label: {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.red)
            }
            .help("Stop Session")
        }
    }

    private var filePanelHeader: some View {
        HStack {
            Label("File Changes", systemImage: "doc.on.doc")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showFilePanel = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var terminalPanelHeader: some View {
        HStack {
            Label("Terminal Output", systemImage: "terminal")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showTerminalPanel = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Foundry")
                .font(.largeTitle.bold())

            Text("Native Claude Code Interface")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("Create a new session to get started")
                    .foregroundStyle(.tertiary)

                Button {
                    openProject()
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                        .frame(width: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.top, 8)

            if let version = sessionManager.claudeVersion {
                Text("Claude Code \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let id = sessionManager.createSession(projectPath: url.path)
            sessionManager.startSession(id)
        }
    }
}

// MARK: - File Changes Panel

struct FileChangesPanel: View {
    let session: Session

    var body: some View {
        if session.fileChanges.isEmpty {
            VStack {
                Spacer()
                Text("No file changes yet")
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            List(session.fileChanges) { change in
                FileChangeRow(change: change)
            }
            .listStyle(.inset)
        }
    }
}

struct FileChangeRow: View {
    let change: FileChange

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: changeIcon)
                .foregroundStyle(changeColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: change.filePath).lastPathComponent)
                    .font(.system(.body, design: .monospaced))

                Text(change.filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    private var changeIcon: String {
        switch change.changeType {
        case .created: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }

    private var changeColor: Color {
        switch change.changeType {
        case .created: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed: return .blue
        }
    }
}

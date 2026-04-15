import SwiftUI

enum NavigationPage: String, CaseIterable {
    case sessions = "Sessions"
    case skills = "Skills"
    case agents = "Agents"
    case mcp = "MCP Servers"
    case usage = "Usage & Costs"
}

struct MainView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appSettings: AppSettings
    @Binding var showCommandPalette: Bool
    @State private var currentPage: NavigationPage = .sessions

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
            VStack(spacing: 0) {
                // Navigation pages
                List(selection: $currentPage) {
                    Section("Navigation") {
                        ForEach(NavigationPage.allCases, id: \.self) { page in
                            Label(page.rawValue, systemImage: iconForPage(page))
                                .tag(page)
                        }
                    }
                }
                .listStyle(.sidebar)
                .frame(height: 180)

                Divider()

                // Sessions list (always visible)
                SidebarView()
            }
            .frame(minWidth: 240)
        } detail: {
            switch currentPage {
            case .sessions:
                sessionContent
            case .skills:
                SkillsView()
            case .agents:
                AgentsView()
            case .mcp:
                MCPView()
            case .usage:
                UsageView()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarButtons
            }
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        if let session = sessionManager.activeSession {
            sessionDetailView(session)
        } else {
            WelcomeView()
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

                // Right: File changes panel (animated)
                if appSettings.showFilePanel {
                    VStack(spacing: 0) {
                        panelHeader(title: "File Changes", icon: "doc.on.doc") {
                            withAnimation(FoundryAnimation.spring) {
                                appSettings.showFilePanel = false
                            }
                        }
                        FileChangesPanel(session: session)
                    }
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }

            // Bottom: Terminal logs (animated)
            if appSettings.showTerminalPanel {
                VStack(spacing: 0) {
                    panelHeader(title: "Terminal Output", icon: "terminal") {
                        withAnimation(FoundryAnimation.spring) {
                            appSettings.showTerminalPanel = false
                        }
                    }
                    TerminalView(session: session)
                }
                .frame(height: 180)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Status bar
            StatusBarView(session: session)
        }
    }

    private func panelHeader(title: String, icon: String, onClose: @escaping () -> Void) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 5)
        .floatingHeader()
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            showCommandPalette = true
        } label: {
            Image(systemName: "command")
        }
        .help("Command Palette (Cmd+K)")

        if currentPage == .sessions {
            Toggle(isOn: Binding(
                get: { appSettings.showFilePanel },
                set: { newValue in
                    withAnimation(FoundryAnimation.spring) {
                        appSettings.showFilePanel = newValue
                    }
                }
            )) {
                Image(systemName: "doc.on.doc")
            }
            .help("Toggle File Changes Panel (Cmd+Shift+F)")

            Toggle(isOn: Binding(
                get: { appSettings.showTerminalPanel },
                set: { newValue in
                    withAnimation(FoundryAnimation.spring) {
                        appSettings.showTerminalPanel = newValue
                    }
                }
            )) {
                Image(systemName: "terminal")
            }
            .help("Toggle Terminal Panel (Cmd+Shift+T)")

            if let id = sessionManager.activeSessionID,
               sessionManager.activeSession?.status == .running {
                Button {
                    sessionManager.stopSession(id)
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(.red)
                }
                .help("Stop Session (Cmd+.)")
            }
        }
    }

    private func iconForPage(_ page: NavigationPage) -> String {
        switch page {
        case .sessions: return "bubble.left.and.bubble.right"
        case .skills: return "sparkles"
        case .agents: return "person.2.fill"
        case .mcp: return "server.rack"
        case .usage: return "chart.bar.fill"
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var appSettings: AppSettings
    @State private var heroVisible = false

    var recentProjects: [String] {
        let paths = sessionManager.sessions.map(\.projectPath)
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero
            VStack(spacing: Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
                        .fill(GradientTokens.subtle)
                        .frame(width: 96, height: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.accentColor.opacity(0.15), radius: 20, y: 4)
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(GradientTokens.accent)
                }

                Text("Foundry")
                    .font(.largeTitle.bold())

                Text("Native Claude Code Interface")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .opacity(heroVisible ? 1 : 0)
            .offset(y: heroVisible ? 0 : 12)
            .animation(FoundryAnimation.gentle, value: heroVisible)

            Spacer().frame(height: Spacing.xxl)

            // Quick actions
            VStack(spacing: Spacing.md) {
                Button {
                    openProject()
                } label: {
                    Label("Open Project", systemImage: "folder.badge.plus")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("or select a session from the sidebar")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Recent projects
            if !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Recent Projects")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    ForEach(recentProjects, id: \.self) { path in
                        Button {
                            let id = sessionManager.createSession(
                                projectPath: path,
                                model: appSettings.defaultModel
                            )
                            sessionManager.startSession(id)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)

                                Text(Utilities.abbreviatePath(path))
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .glassBackground(cornerRadius: CornerRadius.sm, shadow: false)
                        }
                        .buttonStyle(.plain)
                        .hoverLift()
                    }
                }
                .frame(maxWidth: 400)
                .padding(.top, Spacing.xxl)
            }

            Spacer()

            // Footer
            if let version = sessionManager.claudeVersion {
                HStack(spacing: Spacing.sm) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .glowEffect(color: .green, isActive: true)
                    Text("Claude Code \(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { heroVisible = true }
    }

    private func openProject() {
        if let url = Utilities.showOpenProjectPanel() {
            let id = sessionManager.createSession(
                projectPath: url.path,
                model: appSettings.defaultModel
            )
            sessionManager.startSession(id)
        }
    }
}

// MARK: - File Changes Panel

struct FileChangesPanel: View {
    let session: Session

    var body: some View {
        if session.fileChanges.isEmpty {
            VStack(spacing: Spacing.sm) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.06))
                        .frame(width: 56, height: 56)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                }
                Text("No file changes yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
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

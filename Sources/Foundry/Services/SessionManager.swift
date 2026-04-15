import Foundation
import SwiftUI

/// Central manager for all sessions — observable by SwiftUI views
@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionID: UUID?
    @Published var claudeAvailable: Bool = false
    @Published var claudePath: String?
    @Published var claudeVersion: String?
    @Published var isLoadingHistory: Bool = false

    /// Map from Foundry session UUID to the JSONL file path for lazy loading events
    private var jsonlPaths: [UUID: URL] = [:]
    private var controllers: [UUID: ClaudeProcessController] = [:]
    private var fileMonitors: [UUID: FileMonitor] = [:]
    private let persistence = PersistenceManager()

    /// Reference to app settings (wired from FoundryApp)
    var appSettings: AppSettings?

    var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    init() {
        checkClaudeAvailability()
    }

    // MARK: - Claude Availability

    func checkClaudeAvailability() {
        let result = ClaudeProcessController.checkAvailability()
        claudeAvailable = result.available
        claudePath = result.path
        claudeVersion = result.version

        if claudeAvailable {
            loadClaudeHistory()
        }
    }

    // MARK: - Load ALL real Claude Code sessions from JSONL files

    func loadClaudeHistory() {
        isLoadingHistory = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let discovered = ClaudeHistoryLoader.discoverAllSessions()

            DispatchQueue.main.async {
                guard let self = self else { return }

                // Track existing claude session IDs to avoid duplicates
                let existingClaudeIDs = Set(self.sessions.compactMap(\.claudeSessionID))

                for d in discovered {
                    guard !existingClaudeIDs.contains(d.sessionId) else { continue }

                    let dirName = URL(fileURLWithPath: d.cwd).lastPathComponent
                    var session = Session(
                        name: d.name.isEmpty ? dirName : d.name,
                        projectPath: d.cwd,
                        modelName: d.model
                    )
                    session.claudeSessionID = d.sessionId
                    session.status = .stopped
                    session.createdAt = d.startedAt
                    session.updatedAt = d.startedAt
                    session.tokenUsage = d.usage

                    self.sessions.append(session)
                    self.jsonlPaths[session.id] = d.jsonlPath
                }

                self.sessions.sort { $0.createdAt > $1.createdAt }
                self.isLoadingHistory = false
            }
        }
    }

    /// Load conversation events for a session (lazy - only when selected)
    func loadSessionEvents(for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              sessions[index].events.isEmpty,
              let jsonlPath = jsonlPaths[sessionID] else {
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let events = ClaudeHistoryLoader.loadConversationFromFile(jsonlPath)

            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                self.sessions[idx].events = events
            }
        }
    }

    // MARK: - Session Lifecycle

    func createSession(projectPath: String, name: String? = nil, model: String = "claude-sonnet-4-6") -> UUID {
        let dirName = URL(fileURLWithPath: projectPath).lastPathComponent
        let session = Session(
            name: name ?? dirName,
            projectPath: projectPath,
            modelName: model
        )
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        return session.id
    }

    func startSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let session = sessions[index]
        sessions[index].status = .idle

        let controller = ClaudeProcessController(
            sessionID: sessionID,
            projectPath: session.projectPath,
            modelName: session.modelName,
            claudeSessionID: session.claudeSessionID,
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(sessionID: sessionID, event: event)
                }
            },
            onLog: { [weak self] log in
                Task { @MainActor in
                    self?.handleLog(sessionID: sessionID, log: log)
                }
            },
            onUsage: { [weak self] usage in
                Task { @MainActor in
                    self?.handleUsage(sessionID: sessionID, usage: usage)
                }
            },
            onStatusChange: { [weak self] status in
                Task { @MainActor in
                    self?.handleStatusChange(sessionID: sessionID, status: status)
                }
            }
        )

        controllers[sessionID] = controller

        // Start file monitoring for the project directory
        let monitor = FileMonitor(directoryPath: session.projectPath) { [weak self] path, changeType in
            Task { @MainActor in
                guard let self = self,
                      let index = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                // Avoid duplicates for same path
                if !self.sessions[index].fileChanges.contains(where: { $0.filePath == path && $0.changeType == changeType }) {
                    self.sessions[index].fileChanges.append(
                        FileChange(filePath: path, changeType: changeType)
                    )
                }
            }
        }
        monitor.start()
        fileMonitors[sessionID] = monitor
    }

    func sendMessage(to sessionID: UUID, message: String) {
        if controllers[sessionID] == nil {
            startSession(sessionID)
        }
        guard let controller = controllers[sessionID] else { return }
        controller.sendMessage(message)
    }

    func sendCommand(to sessionID: UUID, command: ClaudeCommand) {
        sendMessage(to: sessionID, message: command.name)
    }

    func stopSession(_ sessionID: UUID) {
        controllers[sessionID]?.stop()
        fileMonitors[sessionID]?.stop()
        fileMonitors.removeValue(forKey: sessionID)
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .stopped
            autoSaveSession(sessions[index])
        }
    }

    func deleteSession(_ sessionID: UUID) {
        controllers[sessionID]?.stop()
        fileMonitors[sessionID]?.stop()
        controllers.removeValue(forKey: sessionID)
        fileMonitors.removeValue(forKey: sessionID)
        jsonlPaths.removeValue(forKey: sessionID)
        persistence.deleteSession(sessionID)
        sessions.removeAll(where: { $0.id == sessionID })
        if activeSessionID == sessionID {
            activeSessionID = sessions.first?.id
        }
    }

    func switchToSession(_ sessionID: UUID) {
        activeSessionID = sessionID
        loadSessionEvents(for: sessionID)
    }

    // MARK: - Event Handling

    private func handleEvent(sessionID: UUID, event: SessionEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].events.append(event)
        sessions[index].updatedAt = Date()

        if event.type == .fileWrite || event.type == .fileEdit {
            if let path = event.metadata?.filePath {
                sessions[index].fileChanges.append(
                    FileChange(filePath: path, changeType: event.type == .fileWrite ? .created : .modified)
                )
            }
        }

        if event.type == .sessionStart {
            if let controller = controllers[sessionID], let csid = controller.claudeSessionID {
                sessions[index].claudeSessionID = csid
            }
        }
    }

    private func handleLog(sessionID: UUID, log: LogEntry) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].rawLogs.append(log)
        if sessions[index].rawLogs.count > 10000 {
            sessions[index].rawLogs.removeFirst(1000)
        }
    }

    private func handleUsage(sessionID: UUID, usage: TokenUsage) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        if usage.estimatedCostUSD > 0 { sessions[index].tokenUsage.estimatedCostUSD = usage.estimatedCostUSD }
        if usage.inputTokens > 0 { sessions[index].tokenUsage.inputTokens = usage.inputTokens }
        if usage.outputTokens > 0 { sessions[index].tokenUsage.outputTokens = usage.outputTokens }
        if usage.cacheReadTokens > 0 { sessions[index].tokenUsage.cacheReadTokens = usage.cacheReadTokens }
        if usage.cacheWriteTokens > 0 { sessions[index].tokenUsage.cacheWriteTokens = usage.cacheWriteTokens }
    }

    private func handleStatusChange(sessionID: UUID, status: SessionStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].status = status

        // Autosave when session becomes idle or stops
        if status == .idle || status == .stopped {
            autoSaveSession(sessions[index])
        }
    }

    // MARK: - Persistence

    private func autoSaveSession(_ session: Session) {
        guard appSettings?.autoSaveSessions == true else { return }
        let sessionCopy = session
        DispatchQueue.global(qos: .utility).async { [persistence] in
            persistence.saveSession(sessionCopy)
        }
    }
}

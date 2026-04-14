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

    private var controllers: [UUID: ClaudeProcessController] = [:]

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

    // MARK: - Load real Claude Code session history

    func loadClaudeHistory() {
        isLoadingHistory = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let claudeSessions = ClaudeHistoryLoader.loadAllClaudeSessions()

            DispatchQueue.main.async {
                guard let self = self else { return }
                // Merge with existing sessions (don't duplicate)
                let existingClaudeIDs = Set(self.sessions.compactMap(\.claudeSessionID))

                for session in claudeSessions {
                    if let cid = session.claudeSessionID, !existingClaudeIDs.contains(cid) {
                        self.sessions.append(session)
                    }
                }

                // Sort by most recent
                self.sessions.sort { $0.updatedAt > $1.updatedAt }
                self.isLoadingHistory = false
            }
        }
    }

    /// Load conversation events for a session from Claude Code history
    func loadSessionEvents(for sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              let claudeSessionID = sessions[index].claudeSessionID else {
            return
        }

        // Only load if events are empty
        guard sessions[index].events.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let events = ClaudeHistoryLoader.loadSessionEvents(claudeSessionId: claudeSessionID)

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
    }

    func sendMessage(to sessionID: UUID, message: String) {
        // Ensure we have a controller
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
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .stopped
        }
    }

    func deleteSession(_ sessionID: UUID) {
        controllers[sessionID]?.stop()
        controllers.removeValue(forKey: sessionID)
        sessions.removeAll(where: { $0.id == sessionID })
        if activeSessionID == sessionID {
            activeSessionID = sessions.first?.id
        }
    }

    func switchToSession(_ sessionID: UUID) {
        activeSessionID = sessionID
        // Load events if not already loaded
        loadSessionEvents(for: sessionID)
    }

    // MARK: - Event Handling

    private func handleEvent(sessionID: UUID, event: SessionEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[index].events.append(event)
        sessions[index].updatedAt = Date()

        // Track file changes
        if event.type == .fileWrite || event.type == .fileEdit {
            if let path = event.metadata?.filePath {
                let change = FileChange(
                    filePath: path,
                    changeType: event.type == .fileWrite ? .created : .modified
                )
                sessions[index].fileChanges.append(change)
            }
        }

        // Capture Claude session ID
        if event.type == .sessionStart {
            if let controller = controllers[sessionID],
               let csid = controller.claudeSessionID {
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

        if usage.estimatedCostUSD > 0 {
            sessions[index].tokenUsage.estimatedCostUSD = usage.estimatedCostUSD
        }
        if usage.inputTokens > 0 {
            sessions[index].tokenUsage.inputTokens = usage.inputTokens
        }
        if usage.outputTokens > 0 {
            sessions[index].tokenUsage.outputTokens = usage.outputTokens
        }
        if usage.cacheReadTokens > 0 {
            sessions[index].tokenUsage.cacheReadTokens = usage.cacheReadTokens
        }
        if usage.cacheWriteTokens > 0 {
            sessions[index].tokenUsage.cacheWriteTokens = usage.cacheWriteTokens
        }
    }

    private func handleStatusChange(sessionID: UUID, status: SessionStatus) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].status = status
    }
}

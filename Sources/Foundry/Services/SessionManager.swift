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

    private var controllers: [UUID: ClaudeProcessController] = [:]
    private let persistence = PersistenceManager()

    var activeSession: Session? {
        guard let id = activeSessionID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    var activeSessionIndex: Int? {
        guard let id = activeSessionID else { return nil }
        return sessions.firstIndex(where: { $0.id == id })
    }

    init() {
        checkClaudeAvailability()
        loadPersistedSessions()
    }

    // MARK: - Claude Availability

    func checkClaudeAvailability() {
        let result = ClaudeProcessController.checkAvailability()
        claudeAvailable = result.available
        claudePath = result.path
        claudeVersion = result.version
    }

    // MARK: - Session Lifecycle

    func createSession(projectPath: String, name: String? = nil, model: String = "claude-sonnet-4-6") -> UUID {
        let dirName = URL(fileURLWithPath: projectPath).lastPathComponent
        let session = Session(
            name: name ?? dirName,
            projectPath: projectPath,
            modelName: model
        )
        sessions.append(session)
        activeSessionID = session.id
        return session.id
    }

    func startSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let session = sessions[index]
        let controller = ClaudeProcessController(
            sessionID: sessionID,
            projectPath: session.projectPath,
            modelName: session.modelName,
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
            onExit: { [weak self] status in
                Task { @MainActor in
                    self?.handleProcessExit(sessionID: sessionID, status: status)
                }
            }
        )

        controllers[sessionID] = controller

        do {
            try controller.start()
            sessions[index].status = .running
            sessions[index].processID = controller.processIdentifier
            sessions[index].events.append(
                SessionEvent(type: .sessionStart, content: "Session started for \(session.projectPath)")
            )
        } catch {
            sessions[index].status = .error
            sessions[index].events.append(
                SessionEvent(type: .error, content: error.localizedDescription)
            )
        }
    }

    func sendMessage(to sessionID: UUID, message: String) {
        guard let controller = controllers[sessionID] else { return }
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        sessions[index].status = .running
        controller.sendMessage(message)
    }

    func sendCommand(to sessionID: UUID, command: ClaudeCommand) {
        guard let controller = controllers[sessionID] else { return }
        controller.sendCommand(command.name)
    }

    func stopSession(_ sessionID: UUID) {
        controllers[sessionID]?.stop()
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .stopped
        }
    }

    func deleteSession(_ sessionID: UUID) {
        controllers[sessionID]?.kill()
        controllers.removeValue(forKey: sessionID)
        sessions.removeAll(where: { $0.id == sessionID })
        if activeSessionID == sessionID {
            activeSessionID = sessions.first?.id
        }
        persistence.deleteSession(sessionID)
    }

    func switchToSession(_ sessionID: UUID) {
        activeSessionID = sessionID
    }

    // MARK: - Event Handling

    private func handleEvent(sessionID: UUID, event: SessionEvent) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        // For streaming text, merge with last event if same type
        if event.type == .assistantMessage || event.type == .thinking {
            if let lastIndex = sessions[index].events.lastIndex(where: { $0.type == event.type }) {
                sessions[index].events[lastIndex].content += event.content
                sessions[index].updatedAt = Date()
                return
            }
        }

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
    }

    private func handleLog(sessionID: UUID, log: LogEntry) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].rawLogs.append(log)

        // Limit log buffer to prevent memory issues
        if sessions[index].rawLogs.count > 10000 {
            sessions[index].rawLogs.removeFirst(1000)
        }
    }

    private func handleUsage(sessionID: UUID, usage: TokenUsage) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].tokenUsage.inputTokens += usage.inputTokens
        sessions[index].tokenUsage.outputTokens += usage.outputTokens
        sessions[index].tokenUsage.cacheReadTokens += usage.cacheReadTokens
        sessions[index].tokenUsage.cacheWriteTokens += usage.cacheWriteTokens
        if usage.estimatedCostUSD > 0 {
            sessions[index].tokenUsage.estimatedCostUSD = usage.estimatedCostUSD
        }
    }

    private func handleProcessExit(sessionID: UUID, status: Int32) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        if status == 0 {
            sessions[index].status = .idle
        } else {
            sessions[index].status = .error
            sessions[index].events.append(
                SessionEvent(type: .error, content: "Process exited with status \(status)")
            )
        }

        controllers.removeValue(forKey: sessionID)
        saveSession(sessions[index])
    }

    // MARK: - Persistence

    func saveSession(_ session: Session) {
        persistence.saveSession(session)
    }

    func saveAllSessions() {
        for session in sessions {
            persistence.saveSession(session)
        }
    }

    private func loadPersistedSessions() {
        sessions = persistence.loadAllSessions()
        // Mark all loaded sessions as stopped since processes don't survive app restart
        for i in sessions.indices {
            if sessions[i].status == .running || sessions[i].status == .initializing {
                sessions[i].status = .stopped
            }
        }
    }
}

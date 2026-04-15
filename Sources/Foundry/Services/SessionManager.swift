import Foundation
import SwiftUI

/// Central manager for all sessions -- observable by SwiftUI views
@MainActor
class SessionManager: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var activeSessionID: UUID?
    @Published var claudeAvailable: Bool = false
    @Published var claudePath: String?
    @Published var claudeVersion: String?
    @Published var isLoadingHistory: Bool = false

    /// Last error for each session, surfaced to UI for recovery actions
    @Published var sessionErrors: [UUID: SessionSendError] = [:]

    /// Preserved draft messages when sends fail (keyed by session UUID)
    @Published var preservedDrafts: [UUID: String] = [:]

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

    /// Load conversation events for a session (lazy -- only when selected)
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

        // Clear any previous error state
        sessionErrors.removeValue(forKey: sessionID)
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
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleSendError(sessionID: sessionID, error: error)
                }
            }
        )

        controllers[sessionID] = controller

        // Start file monitoring for the project directory
        if FileManager.default.fileExists(atPath: session.projectPath) {
            let monitor = FileMonitor(directoryPath: session.projectPath) { [weak self] path, changeType in
                Task { @MainActor in
                    guard let self = self,
                          let index = self.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
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
    }

    func sendMessage(to sessionID: UUID, message: String) {
        // Clear previous error
        sessionErrors.removeValue(forKey: sessionID)

        // Check if the session needs a fresh controller.
        // A controller must be (re)created when:
        //   - no controller exists yet (history session, first use)
        //   - the session was stopped or errored (controller is stale)
        let needsStart: Bool
        if let controller = controllers[sessionID] {
            if controller.isRunning {
                // Already processing — reject concurrent send
                let error = SessionSendError.sessionBusy
                handleSendError(sessionID: sessionID, error: error)
                preservedDrafts[sessionID] = message
                return
            }
            // Check session status — if stopped/error, recreate controller
            let status = sessions.first(where: { $0.id == sessionID })?.status
            needsStart = (status == .stopped || status == .error || status == .initializing)
        } else {
            needsStart = true
        }

        if needsStart {
            // Clean up old controller if any
            controllers[sessionID]?.stop()
            controllers.removeValue(forKey: sessionID)
            startSession(sessionID)
        }

        guard let controller = controllers[sessionID] else { return }

        // Preserve draft in case send fails
        preservedDrafts[sessionID] = message

        controller.sendMessage(message)
    }

    func sendCommand(to sessionID: UUID, command: ClaudeCommand) {
        sendMessage(to: sessionID, message: command.name)
    }

    func stopSession(_ sessionID: UUID) {
        controllers[sessionID]?.stop()
        controllers.removeValue(forKey: sessionID)
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
        sessionErrors.removeValue(forKey: sessionID)
        preservedDrafts.removeValue(forKey: sessionID)
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

    // MARK: - Recovery Actions

    /// Recreate a session that failed due to stale/invalid session ID.
    /// Creates a fresh controller without the old claudeSessionID.
    func recreateSession(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        // Stop existing controller
        controllers[sessionID]?.stop()
        controllers.removeValue(forKey: sessionID)
        fileMonitors[sessionID]?.stop()
        fileMonitors.removeValue(forKey: sessionID)

        // Clear the stale session reference
        sessions[index].claudeSessionID = nil
        sessions[index].status = .idle
        sessionErrors.removeValue(forKey: sessionID)

        // Restart with a clean controller
        startSession(sessionID)

        // If we have a preserved draft, re-send it
        if let draft = preservedDrafts.removeValue(forKey: sessionID),
           !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendMessage(to: sessionID, message: draft)
        }
    }

    /// Retry the last failed message for a session
    func retryLastMessage(_ sessionID: UUID) {
        sessionErrors.removeValue(forKey: sessionID)

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].status = .idle
        }

        if let draft = preservedDrafts.removeValue(forKey: sessionID),
           !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sendMessage(to: sessionID, message: draft)
        }
    }

    /// Dismiss an error without taking action
    func dismissError(_ sessionID: UUID) {
        sessionErrors.removeValue(forKey: sessionID)
        if let index = sessions.firstIndex(where: { $0.id == sessionID }),
           sessions[index].status == .error {
            sessions[index].status = .idle
        }
    }

    /// Get the preserved draft for a session (if send failed)
    func consumePreservedDraft(_ sessionID: UUID) -> String? {
        preservedDrafts.removeValue(forKey: sessionID)
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

        // On successful output, clear preserved draft (send succeeded)
        if event.type == .assistantMessage || event.type == .sessionStart {
            preservedDrafts.removeValue(forKey: sessionID)
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

    private func handleSendError(sessionID: UUID, error: SessionSendError) {
        sessionErrors[sessionID] = error

        // If the error suggests recreating, the user can trigger it from the UI.
        // Log the structured error for diagnostics.
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[index].rawLogs.append(LogEntry(
                source: .system,
                content: "[SessionManager] Send error: \(error.userMessage) | retryable=\(error.isRetryable) | shouldRecreate=\(error.shouldRecreateSession)"
            ))
        }
    }

    // MARK: - Session Organization

    func togglePin(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isPinned.toggle()
        autoSaveSession(sessions[index])
    }

    func toggleFavorite(_ sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].isFavorite.toggle()
        autoSaveSession(sessions[index])
    }

    func updateSessionNotes(_ sessionID: UUID, notes: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].notes = notes
        autoSaveSession(sessions[index])
    }

    func renameSession(_ sessionID: UUID, name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sessions[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        autoSaveSession(sessions[index])
    }

    func addTag(_ sessionID: UUID, tag: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !sessions[index].tags.contains(trimmed) else { return }
        sessions[index].tags.append(trimmed)
        autoSaveSession(sessions[index])
    }

    func removeTag(_ sessionID: UUID, tag: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].tags.removeAll { $0 == tag }
        autoSaveSession(sessions[index])
    }

    // MARK: - Search

    /// Search across all sessions for matching content
    func searchSessions(query: String) -> [SearchResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var results: [SearchResult] = []

        for session in sessions {
            // Match session name
            if session.name.localizedCaseInsensitiveContains(q) {
                results.append(SearchResult(
                    sessionID: session.id,
                    sessionName: session.name,
                    matchType: .sessionName,
                    preview: session.name,
                    timestamp: session.updatedAt
                ))
            }

            // Match project path
            if session.projectPath.localizedCaseInsensitiveContains(q) {
                results.append(SearchResult(
                    sessionID: session.id,
                    sessionName: session.name,
                    matchType: .projectPath,
                    preview: session.projectPath,
                    timestamp: session.updatedAt
                ))
            }

            // Match message content
            for event in session.events {
                if event.content.localizedCaseInsensitiveContains(q) {
                    let preview = extractSearchPreview(from: event.content, query: q)
                    results.append(SearchResult(
                        sessionID: session.id,
                        sessionName: session.name,
                        matchType: event.type == .userInput ? .userMessage : .assistantMessage,
                        preview: preview,
                        timestamp: event.timestamp
                    ))
                    break // One match per session per type is enough
                }
            }

            // Match file changes
            for change in session.fileChanges {
                if change.filePath.localizedCaseInsensitiveContains(q) {
                    results.append(SearchResult(
                        sessionID: session.id,
                        sessionName: session.name,
                        matchType: .fileChange,
                        preview: change.filePath,
                        timestamp: change.timestamp
                    ))
                    break
                }
            }

            // Match notes
            if !session.notes.isEmpty && session.notes.localizedCaseInsensitiveContains(q) {
                results.append(SearchResult(
                    sessionID: session.id,
                    sessionName: session.name,
                    matchType: .sessionNotes,
                    preview: session.notes,
                    timestamp: session.updatedAt
                ))
            }

            // Match tags
            for tag in session.tags where tag.contains(q) {
                results.append(SearchResult(
                    sessionID: session.id,
                    sessionName: session.name,
                    matchType: .tag,
                    preview: tag,
                    timestamp: session.updatedAt
                ))
                break
            }
        }

        return results.sorted { $0.timestamp > $1.timestamp }
    }

    private func extractSearchPreview(from content: String, query: String) -> String {
        let lower = content.lowercased()
        guard let range = lower.range(of: query) else {
            return String(content.prefix(120))
        }
        let matchStart = content.distance(from: content.startIndex, to: range.lowerBound)
        let previewStart = max(0, matchStart - 40)
        let startIdx = content.index(content.startIndex, offsetBy: previewStart)
        let endIdx = content.index(startIdx, offsetBy: min(120, content.distance(from: startIdx, to: content.endIndex)))
        var preview = String(content[startIdx..<endIdx])
        if previewStart > 0 { preview = "..." + preview }
        if endIdx < content.endIndex { preview += "..." }
        return preview
    }

    /// Unique project paths across all sessions
    var recentProjects: [String] {
        let paths = sessions.map(\.projectPath)
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// Sessions grouped by project path
    var sessionsByProject: [String: [Session]] {
        Dictionary(grouping: sessions, by: \.projectPath)
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

// MARK: - Search Result

struct SearchResult: Identifiable, Sendable {
    let id = UUID()
    let sessionID: UUID
    let sessionName: String
    let matchType: SearchMatchType
    let preview: String
    let timestamp: Date
}

enum SearchMatchType: String, Sendable {
    case sessionName = "Session"
    case projectPath = "Project"
    case userMessage = "Message"
    case assistantMessage = "Response"
    case fileChange = "File"
    case sessionNotes = "Notes"
    case tag = "Tag"
}

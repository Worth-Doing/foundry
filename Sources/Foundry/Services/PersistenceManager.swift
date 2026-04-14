import Foundation

/// Manages local persistence of sessions and settings
final class PersistenceManager: Sendable {
    private let baseDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = appSupport.appendingPathComponent("Foundry", isDirectory: true)

        // Ensure directories exist
        let sessionsDir = baseDirectory.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    // MARK: - Sessions

    func saveSession(_ session: Session) {
        let url = sessionURL(for: session.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save session \(session.id): \(error)")
        }
    }

    func loadSession(_ id: UUID) -> Session? {
        let url = sessionURL(for: id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Session.self, from: data)
    }

    func loadAllSessions() -> [Session] {
        let sessionsDir = baseDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Session? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Session.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSession(_ id: UUID) {
        let url = sessionURL(for: id)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Settings

    func saveSetting<T: Encodable>(key: String, value: T) {
        let url = baseDirectory.appendingPathComponent("settings.json")
        var settings = loadSettings()
        if let data = try? JSONEncoder().encode(value),
           let json = try? JSONSerialization.jsonObject(with: data) {
            settings[key] = json
        }
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func loadSettings() -> [String: Any] {
        let url = baseDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    // MARK: - Private

    private func sessionURL(for id: UUID) -> URL {
        baseDirectory
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("\(id.uuidString).json")
    }
}

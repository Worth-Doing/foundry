import Foundation

/// Monitors a project directory for file system changes using DispatchSource
final class FileMonitor: Sendable {
    private let directoryPath: String
    private let onChange: @Sendable (String, FileChangeType) -> Void

    private nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
    private nonisolated(unsafe) var fileDescriptor: Int32 = -1
    private nonisolated(unsafe) var knownFiles: [String: Date] = [:]
    private let monitorQueue = DispatchQueue(label: "com.foundry.filemonitor", qos: .utility)
    private let lock = NSLock()

    init(directoryPath: String, onChange: @escaping @Sendable (String, FileChangeType) -> Void) {
        self.directoryPath = directoryPath
        self.onChange = onChange
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }

        // Take initial snapshot
        knownFiles = scanDirectory()

        // Open directory for monitoring
        fileDescriptor = open(directoryPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: monitorQueue
        )

        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        source?.cancel()
        source = nil
    }

    // MARK: - Private

    private func handleDirectoryChange() {
        let newFiles = scanDirectory()

        lock.lock()
        let oldFiles = knownFiles
        lock.unlock()

        // Detect changes
        for (path, modDate) in newFiles {
            if oldFiles[path] == nil {
                onChange(path, .created)
            } else if let oldDate = oldFiles[path], modDate > oldDate {
                onChange(path, .modified)
            }
        }

        for path in oldFiles.keys {
            if newFiles[path] == nil {
                onChange(path, .deleted)
            }
        }

        lock.lock()
        knownFiles = newFiles
        lock.unlock()
    }

    private func scanDirectory() -> [String: Date] {
        var result: [String: Date] = [:]
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directoryPath),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            // Skip common non-essential directories
            let path = fileURL.path
            if path.contains("/node_modules/") || path.contains("/.git/") ||
               path.contains("/.build/") || path.contains("/Build/") {
                continue
            }

            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate {
                result[path] = modDate
            }
        }

        return result
    }

    deinit {
        stop()
    }
}

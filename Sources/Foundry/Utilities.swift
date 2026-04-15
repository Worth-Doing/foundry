import SwiftUI
import AppKit

enum Utilities {

    // MARK: - Path Formatting

    /// Replaces $HOME prefix with ~
    static func abbreviatePath(_ path: String) -> String {
        if let home = ProcessInfo.processInfo.environment["HOME"],
           path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Token Formatting

    /// Formats token count as "1.2M", "3.4K", or raw number
    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    /// Formats token count with decimal separators (e.g. "1,234,567")
    static func formatTokensDetailed(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    // MARK: - Status Display

    /// Maps SessionStatus to display Color
    static func statusColor(for status: SessionStatus) -> Color {
        switch status {
        case .running: return .green
        case .idle: return .blue
        case .initializing: return .orange
        case .error: return .red
        case .stopped: return .secondary
        }
    }

    // MARK: - Model Display

    /// Maps model name string to short display name
    static func displayModelName(_ modelName: String) -> String {
        if modelName.contains("opus") { return "Opus" }
        if modelName.contains("haiku") { return "Haiku" }
        return "Sonnet"
    }

    /// Maps model name string to Color
    static func modelColor(_ modelName: String) -> Color {
        if modelName.contains("opus") { return .purple }
        if modelName.contains("haiku") { return .green }
        return .blue
    }

    // MARK: - Tool Input Formatting

    /// Formats tool_use input dictionary for display
    static func formatToolInput(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Read":
            return input["file_path"] as? String ?? ""
        case "Write":
            let path = input["file_path"] as? String ?? ""
            let contentLen = (input["content"] as? String)?.count ?? 0
            return "\(path) (\(contentLen) chars)"
        case "Edit":
            return input["file_path"] as? String ?? ""
        case "Grep":
            return "grep: \(input["pattern"] as? String ?? "")"
        case "Glob":
            return "glob: \(input["pattern"] as? String ?? "")"
        case "Agent":
            return input["description"] as? String ?? input["prompt"] as? String ?? ""
        case "TaskCreate":
            return input["subject"] as? String ?? ""
        case "TaskUpdate":
            return "Task #\(input["taskId"] as? String ?? "") → \(input["status"] as? String ?? "")"
        default:
            if let data = try? JSONSerialization.data(withJSONObject: input, options: []),
               let str = String(data: data, encoding: .utf8) {
                return String(str.prefix(300))
            }
            return ""
        }
    }

    // MARK: - Project Directory Picker

    /// Presents NSOpenPanel for directory selection, returns selected URL
    @MainActor
    static func showOpenProjectPanel(message: String = "Select a project directory", prompt: String = "Open") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt

        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
}

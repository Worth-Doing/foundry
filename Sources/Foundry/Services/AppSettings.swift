import SwiftUI
import Combine

/// Centralized, persisted app settings using UserDefaults
@MainActor
class AppSettings: ObservableObject {

    // MARK: - Appearance

    @Published var colorScheme: AppColorScheme = .light {
        didSet { UserDefaults.standard.set(colorScheme.rawValue, forKey: Keys.colorScheme) }
    }

    @Published var accentColorName: String = "blue" {
        didSet { UserDefaults.standard.set(accentColorName, forKey: Keys.accentColor) }
    }

    @Published var sidebarWidth: CGFloat = 260 {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: Keys.sidebarWidth) }
    }

    // MARK: - Sessions

    @Published var defaultModel: String = "claude-sonnet-4-6" {
        didSet { UserDefaults.standard.set(defaultModel, forKey: Keys.defaultModel) }
    }

    @Published var autoSaveSessions: Bool = true {
        didSet { UserDefaults.standard.set(autoSaveSessions, forKey: Keys.autoSave) }
    }

    @Published var maxLogEntries: Int = 10000 {
        didSet { UserDefaults.standard.set(maxLogEntries, forKey: Keys.maxLogs) }
    }

    @Published var showRawOutput: Bool = false {
        didSet { UserDefaults.standard.set(showRawOutput, forKey: Keys.showRaw) }
    }

    // MARK: - Permissions

    @Published var permissionMode: String = "default" {
        didSet { UserDefaults.standard.set(permissionMode, forKey: Keys.permissionMode) }
    }

    // MARK: - UI State

    @Published var showTerminalPanel: Bool = false {
        didSet { UserDefaults.standard.set(showTerminalPanel, forKey: Keys.showTerminal) }
    }

    @Published var showFilePanel: Bool = false {
        didSet { UserDefaults.standard.set(showFilePanel, forKey: Keys.showFilePanel) }
    }

    // MARK: - Color Scheme

    enum AppColorScheme: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var swiftUIScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }

        var icon: String {
            switch self {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max.fill"
            case .dark: return "moon.fill"
            }
        }
    }

    // MARK: - Keys

    private enum Keys {
        static let colorScheme = "foundry.colorScheme"
        static let accentColor = "foundry.accentColor"
        static let sidebarWidth = "foundry.sidebarWidth"
        static let defaultModel = "foundry.defaultModel"
        static let autoSave = "foundry.autoSave"
        static let maxLogs = "foundry.maxLogEntries"
        static let showRaw = "foundry.showRawOutput"
        static let permissionMode = "foundry.permissionMode"
        static let showTerminal = "foundry.showTerminalPanel"
        static let showFilePanel = "foundry.showFilePanel"
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard

        if let raw = d.string(forKey: Keys.colorScheme),
           let scheme = AppColorScheme(rawValue: raw) {
            colorScheme = scheme
        }

        if let accent = d.string(forKey: Keys.accentColor), !accent.isEmpty {
            accentColorName = accent
        }

        if d.object(forKey: Keys.sidebarWidth) != nil {
            sidebarWidth = CGFloat(d.double(forKey: Keys.sidebarWidth))
        }

        if let model = d.string(forKey: Keys.defaultModel), !model.isEmpty {
            defaultModel = model
        }

        if d.object(forKey: Keys.autoSave) != nil {
            autoSaveSessions = d.bool(forKey: Keys.autoSave)
        }

        if d.object(forKey: Keys.maxLogs) != nil {
            maxLogEntries = d.integer(forKey: Keys.maxLogs)
        }

        if d.object(forKey: Keys.showRaw) != nil {
            showRawOutput = d.bool(forKey: Keys.showRaw)
        }

        if let perm = d.string(forKey: Keys.permissionMode), !perm.isEmpty {
            permissionMode = perm
        }

        if d.object(forKey: Keys.showTerminal) != nil {
            showTerminalPanel = d.bool(forKey: Keys.showTerminal)
        }

        if d.object(forKey: Keys.showFilePanel) != nil {
            showFilePanel = d.bool(forKey: Keys.showFilePanel)
        }
    }

    // MARK: - Helpers

    var resolvedColorScheme: ColorScheme? {
        colorScheme.swiftUIScheme
    }

    var modelDisplayName: String {
        switch defaultModel {
        case let m where m.contains("opus"): return "Claude Opus 4.6"
        case let m where m.contains("haiku"): return "Claude Haiku 4.5"
        default: return "Claude Sonnet 4.6"
        }
    }
}

import Foundation

struct ClaudeCommand: Identifiable, Sendable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let icon: String
    let category: CommandCategory
    let requiresSession: Bool

    enum CommandCategory: String, Sendable, CaseIterable {
        case session = "Session"
        case code = "Code"
        case git = "Git"
        case config = "Configuration"
        case account = "Account"
        case analysis = "Analysis"
        case system = "System"
    }
}

struct ClaudeCommandRegistry {
    static let allCommands: [ClaudeCommand] = [
        // Session commands
        ClaudeCommand(
            id: "clear", name: "/clear", displayName: "Clear Conversation",
            description: "Clear the current conversation history",
            icon: "trash", category: .session, requiresSession: true
        ),
        ClaudeCommand(
            id: "compact", name: "/compact", displayName: "Compact Conversation",
            description: "Compact conversation to reduce context size",
            icon: "arrow.down.right.and.arrow.up.left", category: .session, requiresSession: true
        ),
        ClaudeCommand(
            id: "resume", name: "/resume", displayName: "Resume Session",
            description: "Resume a previous conversation session",
            icon: "arrow.counterclockwise", category: .session, requiresSession: false
        ),
        ClaudeCommand(
            id: "status", name: "/status", displayName: "Session Status",
            description: "Show current session status and info",
            icon: "info.circle", category: .session, requiresSession: true
        ),

        // Code commands
        ClaudeCommand(
            id: "review", name: "/review", displayName: "Code Review",
            description: "Review code changes on the current branch",
            icon: "eye", category: .code, requiresSession: true
        ),
        ClaudeCommand(
            id: "simplify", name: "/simplify", displayName: "Simplify Code",
            description: "Review and simplify changed code for quality",
            icon: "wand.and.stars", category: .code, requiresSession: true
        ),
        ClaudeCommand(
            id: "security-review", name: "/security-review", displayName: "Security Review",
            description: "Complete security review of pending changes",
            icon: "shield.checkered", category: .code, requiresSession: true
        ),
        ClaudeCommand(
            id: "init", name: "/init", displayName: "Initialize CLAUDE.md",
            description: "Initialize a new CLAUDE.md file with codebase documentation",
            icon: "doc.badge.plus", category: .code, requiresSession: true
        ),

        // Git commands
        ClaudeCommand(
            id: "commit", name: "/commit", displayName: "Git Commit",
            description: "Create a git commit with AI-generated message",
            icon: "arrow.triangle.branch", category: .git, requiresSession: true
        ),
        ClaudeCommand(
            id: "pr-comments", name: "/pr-comments", displayName: "PR Comments",
            description: "View and manage pull request comments",
            icon: "text.bubble", category: .git, requiresSession: true
        ),

        // Configuration commands
        ClaudeCommand(
            id: "config", name: "/config", displayName: "Configuration",
            description: "View and modify Claude Code configuration",
            icon: "gearshape", category: .config, requiresSession: false
        ),
        ClaudeCommand(
            id: "permissions", name: "/permissions", displayName: "Permissions",
            description: "View and manage tool permissions",
            icon: "lock.shield", category: .config, requiresSession: true
        ),
        ClaudeCommand(
            id: "model", name: "/model", displayName: "Switch Model",
            description: "Switch the AI model for the current session",
            icon: "cpu", category: .config, requiresSession: true
        ),
        ClaudeCommand(
            id: "memory", name: "/memory", displayName: "Memory",
            description: "View and edit Claude Code memory files",
            icon: "brain", category: .config, requiresSession: false
        ),
        ClaudeCommand(
            id: "vim", name: "/vim", displayName: "Vim Mode",
            description: "Toggle vim keybinding mode",
            icon: "keyboard", category: .config, requiresSession: false
        ),
        ClaudeCommand(
            id: "terminal-setup", name: "/terminal-setup", displayName: "Terminal Setup",
            description: "Configure terminal integration settings",
            icon: "terminal", category: .config, requiresSession: false
        ),

        // Account commands
        ClaudeCommand(
            id: "login", name: "/login", displayName: "Login",
            description: "Switch to a different account",
            icon: "person.badge.key", category: .account, requiresSession: false
        ),
        ClaudeCommand(
            id: "logout", name: "/logout", displayName: "Logout",
            description: "Sign out of the current account",
            icon: "person.badge.minus", category: .account, requiresSession: false
        ),

        // Analysis commands
        ClaudeCommand(
            id: "cost", name: "/cost", displayName: "Token Usage & Cost",
            description: "Show token usage and estimated cost",
            icon: "dollarsign.circle", category: .analysis, requiresSession: true
        ),
        ClaudeCommand(
            id: "insights", name: "/insights", displayName: "Usage Insights",
            description: "Generate analytics report on Claude Code usage",
            icon: "chart.bar", category: .analysis, requiresSession: false
        ),

        // System commands
        ClaudeCommand(
            id: "help", name: "/help", displayName: "Help",
            description: "Show help information and available commands",
            icon: "questionmark.circle", category: .system, requiresSession: false
        ),
        ClaudeCommand(
            id: "doctor", name: "/doctor", displayName: "Health Check",
            description: "Check the health of your Claude Code installation",
            icon: "stethoscope", category: .system, requiresSession: false
        ),
        ClaudeCommand(
            id: "bug", name: "/bug", displayName: "Report Bug",
            description: "Report a bug in Claude Code",
            icon: "ladybug", category: .system, requiresSession: false
        ),
        ClaudeCommand(
            id: "schedule", name: "/schedule", displayName: "Scheduled Agents",
            description: "Create and manage scheduled remote agents",
            icon: "calendar.badge.clock", category: .system, requiresSession: false
        ),
        ClaudeCommand(
            id: "loop", name: "/loop", displayName: "Recurring Tasks",
            description: "Run a prompt or command on a recurring interval",
            icon: "repeat", category: .system, requiresSession: true
        ),
    ]

    static func search(_ query: String) -> [ClaudeCommand] {
        if query.isEmpty { return allCommands }
        let lower = query.lowercased()
        return allCommands.filter { cmd in
            cmd.name.lowercased().contains(lower) ||
            cmd.displayName.lowercased().contains(lower) ||
            cmd.description.lowercased().contains(lower)
        }
    }

    static func byCategory() -> [(ClaudeCommand.CommandCategory, [ClaudeCommand])] {
        ClaudeCommand.CommandCategory.allCases.compactMap { category in
            let cmds = allCommands.filter { $0.category == category }
            return cmds.isEmpty ? nil : (category, cmds)
        }
    }
}

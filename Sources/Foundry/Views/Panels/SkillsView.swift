import SwiftUI

struct SkillsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var skills: [SkillInfo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showAddSheet = false

    struct SkillInfo: Identifiable {
        let id = UUID()
        let name: String
        let description: String
        let source: String
        let isInstalled: Bool
    }

    var filteredSkills: [SkillInfo] {
        if searchText.isEmpty { return skills }
        return skills.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Skills", systemImage: "sparkles")
                    .font(.title2.bold())

                Spacer()

                Button {
                    loadSkills()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add skill")
            }
            .padding()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search skills...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)

            Divider().padding(.top, 8)

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading skills...")
                Spacer()
            } else if filteredSkills.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No skills found")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredSkills) { skill in
                        SkillRow(skill: skill)
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadSkills() }
        .sheet(isPresented: $showAddSheet) {
            AddSkillSheet(isPresented: $showAddSheet, onAdd: { loadSkills() })
                .environmentObject(sessionManager)
        }
    }

    private func loadSkills() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [SkillInfo] = []

            // Load built-in slash commands
            let builtinSkills = [
                ("update-config", "Configure Claude Code settings and hooks"),
                ("simplify", "Review and simplify code for quality"),
                ("loop", "Run a prompt on a recurring interval"),
                ("schedule", "Create and manage scheduled agents"),
                ("claude-api", "Build and debug Claude API apps"),
                ("compact", "Compact conversation context"),
                ("init", "Initialize a CLAUDE.md file"),
                ("review", "Review code changes"),
                ("security-review", "Security review of pending changes"),
                ("insights", "Generate usage analytics report"),
                ("team-onboarding", "Help teammates ramp on Claude Code"),
                ("commit", "Create a git commit"),
                ("statusline", "Configure status line UI"),
            ]

            for (name, desc) in builtinSkills {
                result.append(SkillInfo(
                    name: name,
                    description: desc,
                    source: "Built-in",
                    isInstalled: true
                ))
            }

            // Load plugin skills
            let pluginDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/plugins/marketplaces/claude-plugins-official/plugins")
            if let dirs = try? FileManager.default.contentsOfDirectory(
                at: pluginDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) {
                for dir in dirs {
                    let pluginJson = dir.appendingPathComponent(".claude-plugin/plugin.json")
                    if let data = try? Data(contentsOf: pluginJson),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let name = json["name"] as? String ?? dir.lastPathComponent
                        let desc = json["description"] as? String ?? ""
                        result.append(SkillInfo(
                            name: name,
                            description: desc,
                            source: "claude-plugins-official",
                            isInstalled: false
                        ))
                    }
                }
            }

            // Check installed
            let installedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/plugins/installed_plugins.json")
            var installedNames: Set<String> = []
            if let data = try? Data(contentsOf: installedPath),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let plugins = json["plugins"] as? [String: Any] {
                for key in plugins.keys {
                    let name = key.components(separatedBy: "@").first ?? key
                    installedNames.insert(name)
                }
            }

            result = result.map { skill in
                if installedNames.contains(skill.name) || skill.source == "Built-in" {
                    return SkillInfo(name: skill.name, description: skill.description,
                                    source: skill.source, isInstalled: true)
                }
                return skill
            }

            DispatchQueue.main.async {
                skills = result
                isLoading = false
            }
        }
    }
}

struct SkillRow: View {
    let skill: SkillsView.SkillInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: skill.isInstalled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(skill.isInstalled ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(skill.name)
                        .font(.system(.body, weight: .medium))

                    Text(skill.source)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }

                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !skill.isInstalled {
                Button("Install") {
                    installPlugin(skill.name)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func installPlugin(_ name: String) {
        guard let path = ClaudeProcessController.findClaudePath() else { return }
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["plugin", "install", name]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

struct AddSkillSheet: View {
    @Binding var isPresented: Bool
    let onAdd: () -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var pluginName = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Install Skill / Plugin")
                .font(.headline)

            Text("Enter the plugin name from claude-plugins-official or a custom source.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Plugin name (e.g. swift-lsp)", text: $pluginName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Install") {
                    guard !pluginName.isEmpty else { return }
                    installPlugin()
                    isPresented = false
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pluginName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func installPlugin() {
        guard let path = ClaudeProcessController.findClaudePath() else { return }
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["plugin", "install", pluginName]
            try? process.run()
            process.waitUntilExit()
        }
    }
}

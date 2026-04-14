import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var agents: [AgentInfo] = []
    @State private var isLoading = true
    @State private var showAddAgent = false

    struct AgentInfo: Identifiable {
        let id = UUID()
        let name: String
        let model: String
        let source: String
        let description: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Agents", systemImage: "person.2.fill")
                    .font(.title2.bold())

                Spacer()

                Button {
                    loadAgents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button {
                    showAddAgent = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add custom agent")
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading agents...")
                Spacer()
            } else {
                List {
                    Section("Built-in Agents") {
                        ForEach(agents.filter { $0.source == "built-in" }) { agent in
                            AgentRow(agent: agent)
                        }
                    }

                    if agents.contains(where: { $0.source == "custom" }) {
                        Section("Custom Agents") {
                            ForEach(agents.filter { $0.source == "custom" }) { agent in
                                AgentRow(agent: agent)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadAgents() }
        .sheet(isPresented: $showAddAgent) {
            AddAgentSheet(isPresented: $showAddAgent, onAdd: { loadAgents() })
        }
    }

    private func loadAgents() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [AgentInfo] = []

            // Run `claude agents` to get live data
            if let path = ClaudeProcessController.findClaudePath() {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["agents"]
                process.standardOutput = pipe
                process.standardError = Pipe()

                if let _ = try? process.run() {
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        result = parseAgentsOutput(output)
                    }
                }
            }

            // Fallback built-in agents if parsing failed
            if result.isEmpty {
                result = [
                    AgentInfo(name: "general-purpose", model: "inherit",
                              source: "built-in",
                              description: "General-purpose agent for complex multi-step tasks"),
                    AgentInfo(name: "Explore", model: "haiku",
                              source: "built-in",
                              description: "Fast agent for exploring codebases"),
                    AgentInfo(name: "Plan", model: "inherit",
                              source: "built-in",
                              description: "Software architect for designing implementation plans"),
                    AgentInfo(name: "statusline-setup", model: "sonnet",
                              source: "built-in",
                              description: "Configure status line settings"),
                ]
            }

            DispatchQueue.main.async {
                agents = result
                isLoading = false
            }
        }
    }

    private func parseAgentsOutput(_ output: String) -> [AgentInfo] {
        var result: [AgentInfo] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Parse "Name · model" format
            if trimmed.contains("·") || trimmed.contains("·") {
                let parts = trimmed.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    let name = parts[0]
                    let model = parts[1]
                    result.append(AgentInfo(
                        name: name, model: model,
                        source: "built-in",
                        description: descriptionForAgent(name)
                    ))
                }
            }
        }
        return result
    }

    private func descriptionForAgent(_ name: String) -> String {
        switch name.lowercased() {
        case "explore": return "Fast agent for exploring codebases, finding files, and searching code"
        case "plan": return "Software architect for designing implementation plans"
        case "general-purpose": return "General-purpose agent for complex multi-step tasks"
        case "statusline-setup": return "Configure Claude Code status line settings"
        default: return "Custom agent"
        }
    }
}

struct AgentRow: View {
    let agent: AgentsView.AgentInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.source == "built-in" ? "person.circle.fill" : "person.badge.plus")
                .font(.title3)
                .foregroundStyle(agent.source == "built-in" ? .blue : .orange)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(.body, design: .monospaced, weight: .medium))

                    Text(agent.model)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.blue)
                }

                Text(agent.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AddAgentSheet: View {
    @Binding var isPresented: Bool
    let onAdd: () -> Void
    @State private var agentName = ""
    @State private var agentDescription = ""
    @State private var agentPrompt = ""
    @State private var agentModel = "inherit"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Agent")
                .font(.headline)

            Text("Custom agents are defined in settings.json or via --agents flag.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                TextField("Name", text: $agentName)
                TextField("Description", text: $agentDescription)

                Picker("Model", selection: $agentModel) {
                    Text("Inherit (parent model)").tag("inherit")
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }

                VStack(alignment: .leading) {
                    Text("System Prompt")
                        .font(.caption)
                    TextEditor(text: $agentPrompt)
                        .frame(height: 100)
                        .font(.system(.callout, design: .monospaced))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add to Settings") {
                    saveAgent()
                    isPresented = false
                    onAdd()
                }
                .buttonStyle(.borderedProminent)
                .disabled(agentName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }

    private func saveAgent() {
        // Read current settings, add agent definition
        let settingsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        var settings: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var agents = settings["agents"] as? [String: Any] ?? [:]
        agents[agentName] = [
            "description": agentDescription,
            "prompt": agentPrompt,
            "model": agentModel
        ] as [String: Any]
        settings["agents"] = agents

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) {
            try? data.write(to: settingsPath, options: .atomic)
        }
    }
}

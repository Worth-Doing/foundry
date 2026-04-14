import SwiftUI

struct MCPView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var servers: [MCPServerInfo] = []
    @State private var isLoading = true
    @State private var showAddServer = false

    struct MCPServerInfo: Identifiable {
        let id = UUID()
        let name: String
        let type: String
        let command: String
        let args: [String]
        let scope: String
        let source: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("MCP Servers", systemImage: "server.rack")
                    .font(.title2.bold())

                Spacer()

                Button {
                    loadServers()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button {
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Add MCP server")
            }
            .padding()

            Divider()

            if isLoading {
                Spacer()
                ProgressView("Loading MCP servers...")
                Spacer()
            } else if servers.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)

                    Text("No MCP Servers Configured")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("MCP servers extend Claude Code with custom tools and data sources.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 350)

                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add MCP Server", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                Spacer()
            } else {
                List {
                    ForEach(servers) { server in
                        MCPServerRow(server: server, onRemove: {
                            removeServer(server.name, scope: server.scope)
                        })
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadServers() }
        .sheet(isPresented: $showAddServer) {
            AddMCPServerSheet(isPresented: $showAddServer, onAdd: { loadServers() })
        }
    }

    private func loadServers() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [MCPServerInfo] = []

            // Run `claude mcp list` for each scope
            for scope in ["user", "project", "local"] {
                if let output = runClaudeCommand(["mcp", "list", "-s", scope]) {
                    let parsed = parseMCPList(output, scope: scope)
                    result.append(contentsOf: parsed)
                }
            }

            // Also check .mcp.json files
            let homeMCP = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mcp.json")
            if let data = try? Data(contentsOf: homeMCP),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let mcpServers = json["mcpServers"] as? [String: Any] {
                for (name, config) in mcpServers {
                    if let cfg = config as? [String: Any] {
                        result.append(MCPServerInfo(
                            name: name,
                            type: cfg["type"] as? String ?? "stdio",
                            command: cfg["command"] as? String ?? "",
                            args: cfg["args"] as? [String] ?? [],
                            scope: "global",
                            source: "~/.mcp.json"
                        ))
                    }
                }
            }

            DispatchQueue.main.async {
                servers = result
                isLoading = false
            }
        }
    }

    private func parseMCPList(_ output: String, scope: String) -> [MCPServerInfo] {
        var result: [MCPServerInfo] = []
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Look for server entries like "  name: command args..."
            if !trimmed.isEmpty && !trimmed.hasPrefix("No ") && !trimmed.contains("configured") {
                let parts = trimmed.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 {
                    let name = parts[0]
                    let rest = parts.dropFirst().joined(separator: ":")
                    let cmdParts = rest.components(separatedBy: " ")
                    result.append(MCPServerInfo(
                        name: name,
                        type: "stdio",
                        command: cmdParts.first ?? "",
                        args: Array(cmdParts.dropFirst()),
                        scope: scope,
                        source: "claude mcp"
                    ))
                }
            }
        }
        return result
    }

    private func removeServer(_ name: String, scope: String) {
        DispatchQueue.global().async {
            _ = runClaudeCommand(["mcp", "remove", name, "-s", scope])
            DispatchQueue.main.async {
                loadServers()
            }
        }
    }

    private func runClaudeCommand(_ args: [String]) -> String? {
        guard let path = ClaudeProcessController.findClaudePath() else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

struct MCPServerRow: View {
    let server: MCPView.MCPServerInfo
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.system(.body, design: .monospaced, weight: .medium))

                    Text(server.scope)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.orange)

                    Text(server.type)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.blue)
                }

                Text("\(server.command) \(server.args.joined(separator: " "))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}

struct AddMCPServerSheet: View {
    @Binding var isPresented: Bool
    let onAdd: () -> Void
    @State private var serverName = ""
    @State private var serverType = "stdio"
    @State private var command = ""
    @State private var arguments = ""
    @State private var scope = "user"
    @State private var envVars = ""
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add MCP Server")
                .font(.headline)

            Form {
                TextField("Server Name", text: $serverName)

                Picker("Type", selection: $serverType) {
                    Text("stdio").tag("stdio")
                    Text("sse").tag("sse")
                }

                TextField("Command (e.g. npx)", text: $command)
                TextField("Arguments (space-separated)", text: $arguments)

                Picker("Scope", selection: $scope) {
                    Text("User (global)").tag("user")
                    Text("Project").tag("project")
                    Text("Local").tag("local")
                }

                VStack(alignment: .leading) {
                    Text("Environment Variables (KEY=VALUE, one per line)")
                        .font(.caption)
                    TextEditor(text: $envVars)
                        .frame(height: 60)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Server") {
                    addServer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverName.isEmpty || command.isEmpty || isAdding)
            }
        }
        .padding(24)
        .frame(width: 500, height: 450)
    }

    private func addServer() {
        guard let path = ClaudeProcessController.findClaudePath() else { return }
        isAdding = true

        DispatchQueue.global().async {
            let process = Process()
            var args = ["mcp", "add", serverName, "-s", scope, "--", command]
            args.append(contentsOf: arguments.components(separatedBy: " ").filter { !$0.isEmpty })

            // Add env vars
            let envPairs = envVars.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.contains("=") }

            for pair in envPairs {
                args.insert(contentsOf: ["-e", pair], at: 4)
            }

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            try? process.run()
            process.waitUntilExit()

            DispatchQueue.main.async {
                isAdding = false
                isPresented = false
                onAdd()
            }
        }
    }
}

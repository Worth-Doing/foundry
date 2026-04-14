import SwiftUI

struct TimelineEventView: View {
    let event: SessionEvent
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Event header
            HStack(spacing: 8) {
                Image(systemName: eventIcon)
                    .foregroundStyle(eventColor)
                    .frame(width: 20)

                Text(eventTitle)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(eventColor)

                if let toolName = event.metadata?.toolName {
                    Text(toolName)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(eventColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Text(event.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Event content
            if isExpanded && !event.content.isEmpty {
                eventContent
                    .padding(.horizontal, 16)
                    .padding(.leading, 28)
                    .padding(.bottom, 8)
            }
        }
        .background(eventBackground)
    }

    @ViewBuilder
    private var eventContent: some View {
        switch event.type {
        case .userInput:
            Text(event.content)
                .font(.system(.body))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

        case .assistantMessage:
            Text(event.content)
                .font(.system(.body))
                .textSelection(.enabled)
                .lineSpacing(3)

        case .thinking:
            Text(event.content)
                .font(.system(.callout))
                .foregroundStyle(.secondary)
                .italic()
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))

        case .toolUse, .bashCommand:
            VStack(alignment: .leading, spacing: 4) {
                if let cmd = event.metadata?.command ?? (event.metadata?.toolName == "Bash" ? event.content : nil),
                   !cmd.isEmpty {
                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                } else if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(isExpanded ? nil : 3)
                }
            }

        case .toolResult, .bashOutput:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(event.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color(.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

        case .error:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(event.content)
                    .font(.system(.callout))
                    .foregroundStyle(.red)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

        case .fileRead, .fileWrite, .fileEdit:
            HStack(spacing: 6) {
                Image(systemName: event.type == .fileRead ? "doc.text" : "doc.badge.ellipsis")
                Text(event.metadata?.filePath ?? event.content)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(6)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))

        case .subAgentSpawn:
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                Text("Sub-agent: \(event.metadata?.agentName ?? "unknown")")
                    .font(.system(.callout, weight: .medium))
            }
            .padding(6)
            .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

        default:
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.system(.callout))
                    .textSelection(.enabled)
            }
        }
    }

    private var eventIcon: String {
        switch event.type {
        case .userInput: return "person.fill"
        case .assistantMessage: return "bubble.left.fill"
        case .thinking: return "brain"
        case .toolUse: return "wrench.fill"
        case .toolResult: return "checkmark.circle"
        case .bashCommand: return "terminal.fill"
        case .bashOutput: return "text.alignleft"
        case .fileRead: return "doc.text"
        case .fileWrite: return "doc.badge.plus"
        case .fileEdit: return "pencil"
        case .search: return "magnifyingglass"
        case .error: return "exclamationmark.triangle.fill"
        case .subAgentSpawn: return "person.2.fill"
        case .subAgentResult: return "person.2"
        case .permissionRequest: return "lock.fill"
        case .permissionResponse: return "lock.open.fill"
        case .costUpdate: return "dollarsign.circle"
        case .sessionStart: return "play.fill"
        case .sessionEnd: return "stop.fill"
        case .systemInfo: return "info.circle"
        }
    }

    private var eventTitle: String {
        switch event.type {
        case .userInput: return "You"
        case .assistantMessage: return "Claude"
        case .thinking: return "Thinking"
        case .toolUse: return "Tool"
        case .toolResult: return "Result"
        case .bashCommand: return "Command"
        case .bashOutput: return "Output"
        case .fileRead: return "Read"
        case .fileWrite: return "Write"
        case .fileEdit: return "Edit"
        case .search: return "Search"
        case .error: return "Error"
        case .subAgentSpawn: return "Agent"
        case .subAgentResult: return "Agent Result"
        case .permissionRequest: return "Permission"
        case .permissionResponse: return "Granted"
        case .costUpdate: return "Cost"
        case .sessionStart: return "Started"
        case .sessionEnd: return "Ended"
        case .systemInfo: return "System"
        }
    }

    private var eventColor: Color {
        switch event.type {
        case .userInput: return .blue
        case .assistantMessage: return .primary
        case .thinking: return .secondary
        case .toolUse, .bashCommand: return .orange
        case .toolResult, .bashOutput: return .green
        case .fileRead: return .cyan
        case .fileWrite, .fileEdit: return .mint
        case .search: return .indigo
        case .error: return .red
        case .subAgentSpawn, .subAgentResult: return .purple
        case .permissionRequest, .permissionResponse: return .yellow
        case .costUpdate: return .secondary
        case .sessionStart, .sessionEnd: return .secondary
        case .systemInfo: return .secondary
        }
    }

    private var eventBackground: Color {
        switch event.type {
        case .userInput: return .blue.opacity(0.03)
        case .error: return .red.opacity(0.03)
        case .thinking: return .clear
        default: return .clear
        }
    }
}

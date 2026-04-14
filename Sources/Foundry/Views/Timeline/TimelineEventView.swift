import SwiftUI

struct TimelineEventView: View {
    let event: SessionEvent
    @State private var isExpanded = true
    @State private var isHovered = false

    var body: some View {
        Group {
            switch event.type {
            case .userInput:
                userBubble
            case .assistantMessage:
                assistantBubble
            case .thinking:
                thinkingBubble
            case .toolUse, .bashCommand:
                toolBubble
            case .toolResult, .bashOutput:
                resultBubble
            case .error:
                errorBubble
            case .fileRead, .fileWrite, .fileEdit:
                fileBubble
            case .search:
                searchBubble
            case .subAgentSpawn:
                agentBubble
            case .systemInfo, .permissionRequest, .permissionResponse:
                systemBubble
            default:
                if !event.content.isEmpty {
                    systemBubble
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .onHover { isHovered = $0 }
    }

    // MARK: - User message

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 80)

            VStack(alignment: .trailing, spacing: 4) {
                Text(event.content)
                    .font(.system(.body))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if isHovered {
                    Text(event.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Assistant message

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                MarkdownView(text: event.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if isHovered {
                    Text(event.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Thinking

    private var thinkingBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(isExpanded: $isExpanded) {
                MarkdownView(text: event.content)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Thinking...")
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 80)
        }
    }

    // MARK: - Tool use / Bash command

    private var toolBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: event.type == .bashCommand ? "terminal.fill" : "wrench.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                // Header
                HStack(spacing: 6) {
                    Text(event.metadata?.toolName ?? "Tool")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                    if isHovered {
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Content
                if isExpanded, let cmd = event.metadata?.command, !cmd.isEmpty {
                    Text(cmd)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                } else if isExpanded, !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(6)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Tool result

    private var resultBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 2)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    ScrollView {
                        Text(event.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(8)
                    .background(Color(.textBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(String(event.content.prefix(80)) + (event.content.count > 80 ? "..." : ""))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(8)
                }
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Error

    private var errorBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Text(event.content)
                .font(.system(.callout))
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 40)
        }
    }

    // MARK: - File operations

    private var fileBubble: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.mint.opacity(0.3))
                .frame(width: 2)
                .padding(.leading, 14)

            HStack(spacing: 8) {
                Image(systemName: fileIcon)
                    .font(.caption)
                    .foregroundStyle(.mint)

                Text(fileLabel)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.mint)

                Text(event.metadata?.filePath ?? event.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }

    // MARK: - Search

    private var searchBubble: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.indigo.opacity(0.3))
                .frame(width: 2)
                .padding(.leading, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.indigo)

                Text(event.metadata?.searchPattern ?? event.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }

    // MARK: - Agent

    private var agentBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Agent")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.purple)

                    if let name = event.metadata?.agentName {
                        Text(name)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if !event.content.isEmpty {
                    Text(event.content)
                        .font(.system(.callout))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 40)
        }
    }

    // MARK: - System

    private var systemBubble: some View {
        HStack {
            Spacer()

            Text(event.content)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: Capsule())

            Spacer()
        }
    }

    // MARK: - Helpers

    private var fileIcon: String {
        switch event.type {
        case .fileRead: return "doc.text"
        case .fileWrite: return "doc.badge.plus"
        case .fileEdit: return "pencil"
        default: return "doc"
        }
    }

    private var fileLabel: String {
        switch event.type {
        case .fileRead: return "READ"
        case .fileWrite: return "WRITE"
        case .fileEdit: return "EDIT"
        default: return "FILE"
        }
    }
}

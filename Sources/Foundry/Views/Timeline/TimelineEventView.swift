import SwiftUI

struct TimelineEventView: View {
    let event: SessionEvent
    @State private var isExpanded = true
    @State private var isHovered = false
    @State private var showCopied = false
    @Environment(\.colorScheme) private var colorScheme

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

    // MARK: - Colors

    private var codeBg: Color {
        colorScheme == .dark
            ? Color(nsColor: .textBackgroundColor)
            : Color.black.opacity(0.03)
    }

    // MARK: - Copy helper

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopied = false
        }
    }

    private var copyButton: some View {
        Button {
            copyToClipboard(event.content)
        } label: {
            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(showCopied ? Color.green : Color.secondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help("Copy to clipboard")
        .transition(.opacity)
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
                    HStack(spacing: Spacing.sm) {
                        copyButton
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                    .fill(GradientTokens.subtle)
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                MarkdownView(text: event.content)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .glassBackground(cornerRadius: CornerRadius.xl, shadow: isHovered)

                if isHovered {
                    HStack(spacing: Spacing.sm) {
                        copyButton
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.leading, Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                    .fill(Color.secondary.opacity(0.08))
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
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: event.type == .bashCommand ? "terminal.fill" : "wrench.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header
                HStack(spacing: Spacing.sm) {
                    Text(event.metadata?.toolName ?? "Tool")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: CornerRadius.sm))

                    if isHovered {
                        copyButton
                        Text(event.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Collapse/expand for long content
                    if contentLength > 200 {
                        Button {
                            withAnimation(FoundryAnimation.micro) { isExpanded.toggle() }
                        } label: {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Content
                if let cmd = event.metadata?.command, !cmd.isEmpty {
                    if isExpanded || cmd.count <= 200 {
                        Text(cmd)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(codeBg, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    } else {
                        Text(String(cmd.prefix(200)) + "...")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(codeBg, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                } else if !event.content.isEmpty {
                    if isExpanded || event.content.count <= 200 {
                        Text(event.content)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(isExpanded ? nil : 6)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(codeBg, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    } else {
                        Text(String(event.content.prefix(200)) + "...")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(codeBg, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                }
            }
            .padding(Spacing.md)
            .glassBackground(cornerRadius: CornerRadius.md, shadow: isHovered)

            Spacer(minLength: 40)
        }
    }

    private var contentLength: Int {
        event.metadata?.command?.count ?? event.content.count
    }

    // MARK: - Tool result

    private var resultBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 2)
                .padding(.leading, 14)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if !isExpanded {
                        Text(String(event.content.prefix(100)) + (event.content.count > 100 ? "..." : ""))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isHovered {
                        copyButton
                    }
                }

                if isExpanded {
                    ScrollView {
                        Text(event.content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding(8)
            .background(codeBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                withAnimation(FoundryAnimation.micro) { isExpanded.toggle() }
            }

            Spacer(minLength: 40)
        }
    }

    // MARK: - Error

    private var errorBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(event.content)
                    .font(.system(.callout))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)

                if let exitCode = event.metadata?.exitCode {
                    Text("Exit code: \(exitCode)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red.opacity(0.7))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.red.opacity(0.15), lineWidth: 1)
            )

            Spacer(minLength: 40)
        }
    }

    // MARK: - File operations

    private var fileBubble: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.mint.opacity(0.25))
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

                Spacer()

                // Open in Finder
                if let path = event.metadata?.filePath {
                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                    .opacity(isHovered ? 1 : 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.mint.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }

    // MARK: - Search

    private var searchBubble: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.indigo.opacity(0.25))
                .frame(width: 2)
                .padding(.leading, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.indigo)

                Text(event.metadata?.toolName ?? "Search")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.indigo)

                Text(event.metadata?.searchPattern ?? event.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    copyButton
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }

    // MARK: - Agent

    private var agentBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
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
                        .lineLimit(isExpanded ? nil : 2)
                }
            }
            .padding(10)
            .background(.purple.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                withAnimation(FoundryAnimation.micro) { isExpanded.toggle() }
            }

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

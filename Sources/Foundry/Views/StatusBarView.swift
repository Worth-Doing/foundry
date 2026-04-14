import SwiftUI

struct StatusBarView: View {
    let session: Session

    var body: some View {
        HStack(spacing: 16) {
            // Session status
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(session.status.rawValue.capitalized)
                    .font(.system(.caption2, weight: .medium))
            }

            Divider()
                .frame(height: 12)

            // Model
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.caption2)
                Text(displayModelName)
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            // Token usage
            HStack(spacing: 4) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                Text(formatTokens(session.tokenUsage.inputTokens))
                    .font(.system(.caption2, design: .monospaced))

                Image(systemName: "arrow.down")
                    .font(.caption2)
                Text(formatTokens(session.tokenUsage.outputTokens))
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            if session.tokenUsage.cacheReadTokens > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "memorychip")
                        .font(.caption2)
                    Text(formatTokens(session.tokenUsage.cacheReadTokens))
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
            }

            Divider()
                .frame(height: 12)

            // Cost
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption2)
                Text(String(format: "$%.4f", session.tokenUsage.estimatedCostUSD))
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            Spacer()

            // File changes count
            if !session.fileChanges.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.caption2)
                    Text("\(session.fileChanges.count) changes")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            // Events count
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                    .font(.caption2)
                Text("\(session.events.count) events")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)

            // Project path
            Text(abbreviatedPath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .frame(height: 24)
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle: return .blue
        case .initializing: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }

    private var displayModelName: String {
        let name = session.modelName
        if name.contains("opus") { return "Opus" }
        if name.contains("sonnet") { return "Sonnet" }
        if name.contains("haiku") { return "Haiku" }
        return name
    }

    private var abbreviatedPath: String {
        let path = session.projectPath
        if let home = ProcessInfo.processInfo.environment["HOME"],
           path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

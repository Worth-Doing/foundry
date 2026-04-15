import SwiftUI

struct StatusBarView: View {
    let session: Session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Session status
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(session.status.rawValue.capitalized)
                    .font(.system(.caption2, weight: .medium))
            }
            .padding(.horizontal, 10)

            statusDivider

            // Model
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 9))
                Text(displayModelName)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
            }
            .foregroundStyle(modelColor)
            .padding(.horizontal, 8)

            statusDivider

            // Token usage
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                    Text(formatTokens(session.tokenUsage.inputTokens))
                        .font(.system(.caption2, design: .monospaced))
                }

                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                    Text(formatTokens(session.tokenUsage.outputTokens))
                        .font(.system(.caption2, design: .monospaced))
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            if session.tokenUsage.cacheReadTokens > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 8))
                    Text(formatTokens(session.tokenUsage.cacheReadTokens))
                        .font(.system(.caption2, design: .monospaced))
                }
                .foregroundStyle(.tertiary)
                .padding(.trailing, 8)
            }

            statusDivider

            // Cost
            HStack(spacing: 3) {
                Text("$")
                    .font(.system(.caption2, weight: .medium))
                Text(String(format: "%.4f", session.tokenUsage.estimatedCostUSD))
                    .font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(session.tokenUsage.estimatedCostUSD > 0 ? .secondary : .quaternary)
            .padding(.horizontal, 8)

            Spacer()

            // File changes count
            if !session.fileChanges.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.system(size: 9))
                    Text("\(session.fileChanges.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }

            // Events count
            HStack(spacing: 3) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 9))
                Text("\(session.events.count)")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)

            // Project path
            Text(abbreviatedPath)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .frame(height: 22)
    }

    private var statusDivider: some View {
        Divider()
            .frame(height: 10)
    }

    private var statusColor: Color {
        Utilities.statusColor(for: session.status)
    }

    private var displayModelName: String {
        Utilities.displayModelName(session.modelName)
    }

    private var modelColor: Color {
        Utilities.modelColor(session.modelName)
    }

    private var abbreviatedPath: String {
        Utilities.abbreviatePath(session.projectPath)
    }

    private func formatTokens(_ count: Int) -> String {
        Utilities.formatTokens(count)
    }
}

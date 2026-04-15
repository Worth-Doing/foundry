import SwiftUI

struct UsageView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedPeriod: TimePeriod = .all
    @Environment(\.colorScheme) private var colorScheme

    enum TimePeriod: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
    }

    var filteredSessions: [Session] {
        let cutoff: Date
        switch selectedPeriod {
        case .today:
            cutoff = Calendar.current.startOfDay(for: Date())
        case .week:
            cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month:
            cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .all:
            cutoff = Date.distantPast
        }
        return sessionManager.sessions.filter { $0.createdAt >= cutoff }
    }

    var totalCost: Double {
        filteredSessions.reduce(0) { $0 + $1.tokenUsage.estimatedCostUSD }
    }

    var totalInputTokens: Int {
        filteredSessions.reduce(0) { $0 + $1.tokenUsage.inputTokens }
    }

    var totalOutputTokens: Int {
        filteredSessions.reduce(0) { $0 + $1.tokenUsage.outputTokens }
    }

    var totalCacheReads: Int {
        filteredSessions.reduce(0) { $0 + $1.tokenUsage.cacheReadTokens }
    }

    var totalCacheWrites: Int {
        filteredSessions.reduce(0) { $0 + $1.tokenUsage.cacheWriteTokens }
    }

    var totalEvents: Int {
        filteredSessions.reduce(0) { $0 + $1.events.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Label("Usage & Costs", systemImage: "chart.bar.fill")
                        .font(.title2.bold())

                    Spacer()

                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 350)
                }
                .padding()

                Divider()

                // Summary cards
                summaryCards
                    .padding()

                Divider()

                // Cost breakdown
                costBreakdown
                    .padding()

                Divider()

                // Per-session table
                sessionTable
                    .padding()
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        HStack(spacing: 16) {
            SummaryCard(
                title: "Total Cost",
                value: String(format: "$%.4f", totalCost),
                icon: "dollarsign.circle.fill",
                color: .green
            )

            SummaryCard(
                title: "Sessions",
                value: "\(filteredSessions.count)",
                icon: "bubble.left.and.bubble.right.fill",
                color: .blue
            )

            SummaryCard(
                title: "Total Tokens",
                value: formatTokens(totalInputTokens + totalOutputTokens),
                icon: "text.word.spacing",
                color: .orange
            )

            SummaryCard(
                title: "Events",
                value: "\(totalEvents)",
                icon: "list.bullet",
                color: .purple
            )
        }
    }

    // MARK: - Cost Breakdown

    private var costBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token Breakdown")
                .font(.headline)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    TokenRow(label: "Input Tokens", count: totalInputTokens, color: .blue)
                    TokenRow(label: "Output Tokens", count: totalOutputTokens, color: .green)
                    TokenRow(label: "Cache Read", count: totalCacheReads, color: .cyan)
                    TokenRow(label: "Cache Write", count: totalCacheWrites, color: .orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Visual bar chart
                VStack(alignment: .leading, spacing: 4) {
                    TokenBar(label: "In", count: totalInputTokens, maxCount: max(totalInputTokens, totalOutputTokens, 1), color: .blue)
                    TokenBar(label: "Out", count: totalOutputTokens, maxCount: max(totalInputTokens, totalOutputTokens, 1), color: .green)
                    TokenBar(label: "Cache R", count: totalCacheReads, maxCount: max(totalCacheReads, totalCacheWrites, 1), color: .cyan)
                    TokenBar(label: "Cache W", count: totalCacheWrites, maxCount: max(totalCacheReads, totalCacheWrites, 1), color: .orange)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Session Table

    private var sessionTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per-Session Breakdown")
                .font(.headline)

            // Table header
            HStack {
                Text("Session")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Project")
                    .frame(width: 150, alignment: .leading)
                Text("Events")
                    .frame(width: 60, alignment: .trailing)
                Text("Input")
                    .frame(width: 80, alignment: .trailing)
                Text("Output")
                    .frame(width: 80, alignment: .trailing)
                Text("Cost")
                    .frame(width: 80, alignment: .trailing)
                Text("Date")
                    .frame(width: 100, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            Divider()

            ForEach(filteredSessions) { session in
                HStack {
                    Text(session.name)
                        .font(.system(.callout, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(URL(fileURLWithPath: session.projectPath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)

                    Text("\(session.events.count)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)

                    Text(formatTokens(session.tokenUsage.inputTokens))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.blue)
                        .frame(width: 80, alignment: .trailing)

                    Text(formatTokens(session.tokenUsage.outputTokens))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                        .frame(width: 80, alignment: .trailing)

                    Text(String(format: "$%.4f", session.tokenUsage.estimatedCostUSD))
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)

                    Text(session.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()
            }

            // Total row
            HStack {
                Text("TOTAL")
                    .font(.system(.callout, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("")
                    .frame(width: 150)

                Text("\(totalEvents)")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .frame(width: 60, alignment: .trailing)

                Text(formatTokens(totalInputTokens))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.blue)
                    .frame(width: 80, alignment: .trailing)

                Text(formatTokens(totalOutputTokens))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 80, alignment: .trailing)

                Text(String(format: "$%.4f", totalCost))
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .frame(width: 80, alignment: .trailing)

                Text("")
                    .frame(width: 100)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
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

// MARK: - Subviews

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(.title2, design: .monospaced, weight: .bold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(colorScheme == .light ? 0.06 : 0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.1), lineWidth: 1)
        )
    }
}

struct TokenRow: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Text(formatTokens(count))
                .font(.system(.callout, design: .monospaced, weight: .medium))
        }
    }

    private func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

struct TokenBar: View {
    let label: String
    let count: Int
    let maxCount: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            GeometryReader { geo in
                let width = max(2, geo.size.width * CGFloat(count) / CGFloat(max(maxCount, 1)))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.7))
                    .frame(width: width)
            }
            .frame(height: 16)
        }
    }
}

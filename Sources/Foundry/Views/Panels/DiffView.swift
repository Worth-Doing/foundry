import SwiftUI

struct DiffView: View {
    let diffLines: [DiffLine]
    let fileName: String

    @State private var viewMode: DiffViewMode = .unified
    @Environment(\.colorScheme) private var colorScheme

    enum DiffViewMode: String, CaseIterable {
        case unified = "Unified"
        case sideBySide = "Side by Side"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.system(.body, design: .monospaced, weight: .medium))

                Spacer()

                Picker("View", selection: $viewMode) {
                    ForEach(DiffViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Diff content
            ScrollView([.horizontal, .vertical]) {
                switch viewMode {
                case .unified:
                    unifiedDiff
                case .sideBySide:
                    sideBySideDiff
                }
            }
            .font(.system(.callout, design: .monospaced))
        }
    }

    private var unifiedDiff: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diffLines) { line in
                HStack(spacing: 0) {
                    // Line numbers
                    Group {
                        Text(line.oldLineNumber.map { String($0) } ?? "")
                            .frame(width: 40, alignment: .trailing)
                        Text(line.newLineNumber.map { String($0) } ?? "")
                            .frame(width: 40, alignment: .trailing)
                    }
                    .foregroundStyle(.tertiary)
                    .font(.system(.caption2, design: .monospaced))

                    // Prefix
                    Text(linePrefix(for: line.type))
                        .frame(width: 16, alignment: .center)
                        .foregroundStyle(lineColor(for: line.type))

                    // Content
                    Text(line.content)
                        .foregroundStyle(lineColor(for: line.type))
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(lineBackground(for: line.type))
            }
        }
    }

    private var sideBySideDiff: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left (old)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines.filter { $0.type != .addition }) { line in
                    HStack(spacing: 0) {
                        Text(line.oldLineNumber.map { String($0) } ?? "")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(.tertiary)
                            .font(.system(.caption2, design: .monospaced))

                        Text(line.content)
                            .foregroundStyle(lineColor(for: line.type))
                            .textSelection(.enabled)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(lineBackground(for: line.type))
                }
            }

            Divider()

            // Right (new)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(diffLines.filter { $0.type != .deletion }) { line in
                    HStack(spacing: 0) {
                        Text(line.newLineNumber.map { String($0) } ?? "")
                            .frame(width: 40, alignment: .trailing)
                            .foregroundStyle(.tertiary)
                            .font(.system(.caption2, design: .monospaced))

                        Text(line.content)
                            .foregroundStyle(lineColor(for: line.type))
                            .textSelection(.enabled)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(lineBackground(for: line.type))
                }
            }
        }
    }

    private func linePrefix(for type: DiffLineType) -> String {
        switch type {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        case .header: return "@"
        }
    }

    private func lineColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return colorScheme == .dark ? .green : Color(red: 0.13, green: 0.55, blue: 0.13)
        case .deletion: return colorScheme == .dark ? .red : Color(red: 0.7, green: 0.15, blue: 0.15)
        case .context: return .primary
        case .header: return .cyan
        }
    }

    private func lineBackground(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return colorScheme == .dark ? .green.opacity(0.08) : Color(red: 0.85, green: 0.95, blue: 0.85)
        case .deletion: return colorScheme == .dark ? .red.opacity(0.08) : Color(red: 0.95, green: 0.87, blue: 0.87)
        case .context: return .clear
        case .header: return .cyan.opacity(0.05)
        }
    }
}

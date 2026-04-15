import SwiftUI

struct TerminalView: View {
    let session: Session
    @State private var filterSource: LogSource? = nil
    @State private var autoScroll = true
    @State private var searchText = ""
    @Environment(\.colorScheme) private var colorScheme

    var filteredLogs: [LogEntry] {
        var logs = session.rawLogs

        if let source = filterSource {
            logs = logs.filter { $0.source == source }
        }

        if !searchText.isEmpty {
            logs = logs.filter { $0.content.localizedCaseInsensitiveContains(searchText) }
        }

        return logs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                // Source filter
                Picker("", selection: $filterSource) {
                    Text("All").tag(nil as LogSource?)
                    Text("stdout").tag(LogSource.stdout as LogSource?)
                    Text("stderr").tag(LogSource.stderr as LogSource?)
                    Text("system").tag(LogSource.system as LogSource?)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Filter logs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))

                Spacer()

                Text("\(filteredLogs.count) entries")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    autoScroll.toggle()
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .foregroundStyle(autoScroll ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Log output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLogs) { log in
                            LogLineView(log: log)
                                .id(log.id)
                        }
                    }
                    .padding(4)
                }
                .font(.system(.caption, design: .monospaced))
                .background(colorScheme == .dark ? Color(nsColor: .textBackgroundColor) : Color.black.opacity(0.02))
                .onChange(of: session.rawLogs.count) { _, _ in
                    if autoScroll, let lastLog = filteredLogs.last {
                        proxy.scrollTo(lastLog.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct LogLineView: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(log.timestamp, format: .dateTime.hour().minute().second())
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)

            Text(sourceLabel)
                .foregroundStyle(sourceColor)
                .frame(width: 40, alignment: .leading)

            Text(log.content.trimmingCharacters(in: .newlines))
                .foregroundStyle(log.source == .stderr ? .red : .primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private var sourceLabel: String {
        switch log.source {
        case .stdout: return "OUT"
        case .stderr: return "ERR"
        case .system: return "SYS"
        }
    }

    private var sourceColor: Color {
        switch log.source {
        case .stdout: return .green
        case .stderr: return .red
        case .system: return .blue
        }
    }
}

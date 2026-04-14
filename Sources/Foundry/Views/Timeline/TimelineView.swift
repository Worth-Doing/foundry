import SwiftUI

struct TimelineView: View {
    let session: Session
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var filterType: EventTypeFilter = .all

    enum EventTypeFilter: String, CaseIterable {
        case all = "All"
        case messages = "Messages"
        case tools = "Tools"
        case files = "Files"
        case errors = "Errors"
    }

    var filteredEvents: [SessionEvent] {
        var events = session.events

        // Apply type filter
        switch filterType {
        case .all:
            // Remove some noise
            events = events.filter { $0.type != .costUpdate && $0.type != .sessionStart }
        case .messages:
            events = events.filter { $0.type == .userInput || $0.type == .assistantMessage }
        case .tools:
            events = events.filter {
                $0.type == .toolUse || $0.type == .toolResult ||
                $0.type == .bashCommand || $0.type == .bashOutput ||
                $0.type == .subAgentSpawn
            }
        case .files:
            events = events.filter {
                $0.type == .fileRead || $0.type == .fileWrite || $0.type == .fileEdit
            }
        case .errors:
            events = events.filter { $0.type == .error }
        }

        // Apply search filter
        if !searchText.isEmpty {
            events = events.filter { event in
                event.content.localizedCaseInsensitiveContains(searchText) ||
                event.metadata?.toolName?.localizedCaseInsensitiveContains(searchText) == true ||
                event.metadata?.filePath?.localizedCaseInsensitiveContains(searchText) == true ||
                event.metadata?.command?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        return events
    }

    var body: some View {
        VStack(spacing: 0) {
            timelineToolbar

            Divider()

            if session.events.isEmpty {
                emptyState
            } else if filteredEvents.isEmpty {
                noMatchState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(filteredEvents) { event in
                                TimelineEventView(event: event)
                                    .id(event.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: session.events.count) { _, _ in
                        if autoScroll, let lastEvent = filteredEvents.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastEvent.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        // Scroll to bottom on appear
                        if let lastEvent = filteredEvents.last {
                            proxy.scrollTo(lastEvent.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 8) {
            // Filter picker
            Picker("Filter", selection: $filterType) {
                ForEach(EventTypeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 350)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 200)

            Spacer()

            Text("\(filteredEvents.count) events")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Auto-scroll")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No events yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Send a message below to start")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("No matching events")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Clear filters") {
                searchText = ""
                filterType = .all
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

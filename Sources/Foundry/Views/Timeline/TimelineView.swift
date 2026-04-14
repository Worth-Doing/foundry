import SwiftUI

struct TimelineView: View {
    let session: Session
    @State private var autoScroll = true
    @State private var searchText = ""

    var filteredEvents: [SessionEvent] {
        let events = session.events.filter { event in
            // Skip internal events
            event.type != .costUpdate && event.type != .sessionStart
        }

        if searchText.isEmpty { return events }

        return events.filter { event in
            event.content.localizedCaseInsensitiveContains(searchText) ||
            event.metadata?.toolName?.localizedCaseInsensitiveContains(searchText) == true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Timeline toolbar
            timelineToolbar

            Divider()

            // Events list
            if filteredEvents.isEmpty {
                emptyState
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
                }
            }
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .default))

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

            Spacer()

            // Event count
            Text("\(filteredEvents.count) events")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Auto-scroll toggle
            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Auto-scroll to latest")
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

            Text("Send a message to start the conversation")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

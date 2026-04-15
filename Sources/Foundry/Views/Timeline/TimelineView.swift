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

        switch filterType {
        case .all:
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

    private var isLoading: Bool {
        session.status == .running
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
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEvents) { event in
                                TimelineEventView(event: event)
                                    .id(event.id)
                            }

                            // Typing indicator
                            if isLoading {
                                TypingIndicator()
                                    .id("typing-indicator")
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: session.events.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: isLoading) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(proxy)
                        }
                    }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard autoScroll else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            if isLoading {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            } else if let lastEvent = filteredEvents.last {
                proxy.scrollTo(lastEvent.id, anchor: .bottom)
            }
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: Spacing.sm) {
            Picker("Filter", selection: $filterType) {
                ForEach(EventTypeFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 350)

            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)

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
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 5)
            .glassBackground(cornerRadius: CornerRadius.sm, shadow: false)
            .frame(maxWidth: 200)

            Spacer()

            Text("\(filteredEvents.count)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(.ultraThinMaterial, in: Capsule())

            Toggle(isOn: $autoScroll) {
                Image(systemName: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Auto-scroll")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .floatingHeader()
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(GradientTokens.subtle)
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.accentColor.opacity(0.1), radius: 20)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(GradientTokens.accent)
            }

            Text("Start a conversation")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Type a message below and press Enter to send")
                .font(.callout)
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

// MARK: - Typing Indicator (animated dots)

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 28, height: 28)
                Text("C")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
            }

            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale(for: i))
                        .opacity(dotOpacity(for: i))
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)
            .glassBackground(cornerRadius: CornerRadius.xl)

            Spacer()
        }
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }

    private func dotScale(for index: Int) -> Double {
        let offset = Double(index) / 3.0
        let adjusted = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.6 + 0.4 * sin(adjusted * .pi * 2)
    }

    private func dotOpacity(for index: Int) -> Double {
        let offset = Double(index) / 3.0
        let adjusted = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.3 + 0.7 * sin(adjusted * .pi * 2)
    }
}

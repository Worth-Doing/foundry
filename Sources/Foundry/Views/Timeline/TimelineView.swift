import SwiftUI

struct TimelineView: View {
    let session: Session
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var filterType: EventTypeFilter = .all
    @State private var collapsedGroups: Set<String> = []

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
            events = events.filter { $0.type == .userInput || $0.type == .assistantMessage || $0.type == .thinking }
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

    /// Group consecutive tool events together for visual pairing
    var groupedEvents: [EventGroup] {
        var groups: [EventGroup] = []
        var currentToolEvents: [SessionEvent] = []

        for event in filteredEvents {
            let isToolRelated = event.type == .toolUse || event.type == .toolResult ||
                                event.type == .bashCommand || event.type == .bashOutput ||
                                event.type == .fileRead || event.type == .fileWrite ||
                                event.type == .fileEdit || event.type == .search ||
                                event.type == .subAgentSpawn || event.type == .subAgentResult

            if isToolRelated {
                currentToolEvents.append(event)
            } else {
                if !currentToolEvents.isEmpty {
                    groups.append(EventGroup(events: currentToolEvents, kind: .toolSequence))
                    currentToolEvents = []
                }
                groups.append(EventGroup(events: [event], kind: .single))
            }
        }

        if !currentToolEvents.isEmpty {
            groups.append(EventGroup(events: currentToolEvents, kind: .toolSequence))
        }

        return groups
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
                            ForEach(Array(groupedEvents.enumerated()), id: \.element.id) { _, group in
                                switch group.kind {
                                case .single:
                                    if let event = group.events.first {
                                        TimelineEventView(event: event)
                                            .id(event.id.uuidString)
                                    }
                                case .toolSequence:
                                    ToolSequenceView(
                                        events: group.events,
                                        isCollapsed: collapsedGroups.contains(group.id),
                                        onToggle: {
                                            withAnimation(FoundryAnimation.micro) {
                                                if collapsedGroups.contains(group.id) {
                                                    collapsedGroups.remove(group.id)
                                                } else {
                                                    collapsedGroups.insert(group.id)
                                                }
                                            }
                                        }
                                    )
                                    .id(group.events.last?.id.uuidString ?? group.id)
                                }
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
                proxy.scrollTo(lastEvent.id.uuidString, anchor: .bottom)
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

            // Event count
            Text("\(filteredEvents.count)")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(.ultraThinMaterial, in: Capsule())

            // Collapse all tool groups
            Button {
                withAnimation(FoundryAnimation.snappy) {
                    if collapsedGroups.isEmpty {
                        for group in groupedEvents where group.kind == .toolSequence {
                            collapsedGroups.insert(group.id)
                        }
                    } else {
                        collapsedGroups.removeAll()
                    }
                }
            } label: {
                Image(systemName: collapsedGroups.isEmpty ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(collapsedGroups.isEmpty ? "Collapse tool groups" : "Expand tool groups")

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

            Text("Type a message below to begin working with Claude Code")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // Quick action hints
            VStack(spacing: Spacing.sm) {
                quickHint(icon: "hammer.fill", text: "Ask Claude to build, fix, or refactor code")
                quickHint(icon: "magnifyingglass", text: "Explore and understand your codebase")
                quickHint(icon: "terminal.fill", text: "Run commands and manage your project")
            }
            .padding(.top, Spacing.md)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func quickHint(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Event Grouping

struct EventGroup: Identifiable {
    let id: String
    let events: [SessionEvent]
    let kind: Kind

    enum Kind {
        case single
        case toolSequence
    }

    init(events: [SessionEvent], kind: Kind) {
        self.events = events
        self.kind = kind
        self.id = events.first?.id.uuidString ?? UUID().uuidString
    }
}

// MARK: - Tool Sequence View (collapsible group)

struct ToolSequenceView: View {
    let events: [SessionEvent]
    let isCollapsed: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    private var toolSummary: String {
        let toolNames = events.compactMap { $0.metadata?.toolName }
        let unique = NSOrderedSet(array: toolNames).array as? [String] ?? toolNames
        return unique.joined(separator: " > ")
    }

    private var fileCount: Int {
        Set(events.compactMap { $0.metadata?.filePath }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                // Collapsed summary bar
                Button(action: onToggle) {
                    HStack(spacing: Spacing.sm) {
                        Rectangle()
                            .fill(Color.orange.opacity(0.4))
                            .frame(width: 3)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)

                        Image(systemName: "wrench.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text("\(events.count) actions")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(toolSummary)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if fileCount > 0 {
                            Text("\(fileCount) files")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(isHovered ? Color.orange.opacity(0.04) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
            } else {
                // Expanded: show all events with collapse header
                VStack(spacing: 0) {
                    // Group header
                    Button(action: onToggle) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)

                            Image(systemName: "wrench.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Text("\(events.count) actions")
                                .font(.system(.caption, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(isHovered ? Color.orange.opacity(0.04) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered = $0 }

                    // Individual events
                    ForEach(events) { event in
                        TimelineEventView(event: event)
                    }
                }
            }
        }
    }
}

// MARK: - Typing Indicator

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

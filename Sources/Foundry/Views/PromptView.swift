import SwiftUI

struct PromptView: View {
    let sessionID: UUID
    @EnvironmentObject var sessionManager: SessionManager
    @State private var promptText = ""
    @State private var contextText = ""
    @State private var showContext = false
    @FocusState private var isFocused: Bool

    private var isSessionActive: Bool {
        sessionManager.sessions.first(where: { $0.id == sessionID })?.status == .running ||
        sessionManager.sessions.first(where: { $0.id == sessionID })?.status == .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context field (optional, collapsible)
            if showContext {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Context")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showContext = false
                            contextText = ""
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }

                    TextEditor(text: $contextText)
                        .font(.system(.callout))
                        .frame(height: 40)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider()
                    .padding(.horizontal, 12)
            }

            // Main input area
            HStack(alignment: .bottom, spacing: 8) {
                // Add context button
                Button {
                    showContext.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                        .foregroundStyle(showContext ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Add context")

                // Text input
                ZStack(alignment: .topLeading) {
                    if promptText.isEmpty {
                        Text("Message Claude...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $promptText)
                        .font(.system(.body))
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                        .frame(minHeight: 32, maxHeight: 100)
                        .fixedSize(horizontal: false, vertical: true)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(4)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘Return)")
            }
            .padding(12)
        }
        .background(.bar)
        .onAppear {
            isFocused = true
        }
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isSessionActive
    }

    private func sendMessage() {
        let message = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        var fullMessage = message
        if showContext && !contextText.isEmpty {
            fullMessage = "Context: \(contextText)\n\n\(message)"
        }

        sessionManager.sendMessage(to: sessionID, message: fullMessage)
        promptText = ""
        contextText = ""
        showContext = false
    }
}

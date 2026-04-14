import SwiftUI

struct PromptView: View {
    let sessionID: UUID
    @EnvironmentObject var sessionManager: SessionManager
    @State private var promptText = ""
    @FocusState private var isFocused: Bool

    private var session: Session? {
        sessionManager.sessions.first(where: { $0.id == sessionID })
    }

    private var isProcessing: Bool {
        session?.status == .running
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text input
            ZStack(alignment: .topLeading) {
                if promptText.isEmpty {
                    Text(isProcessing ? "Claude is working..." : "Message Claude...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $promptText)
                    .font(.system(.body))
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 32, maxHeight: 80)
                    .fixedSize(horizontal: false, vertical: true)
                    .disabled(isProcessing)
            }
            .padding(4)
            .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            // Send / Stop button
            if isProcessing {
                Button {
                    sessionManager.stopSession(sessionID)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Stop (⌘.)")
            } else {
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
        }
        .padding(12)
        .background(.bar)
        .onAppear {
            isFocused = true
        }
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    private func sendMessage() {
        let message = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        sessionManager.sendMessage(to: sessionID, message: message)
        promptText = ""
    }
}

import SwiftUI
import AppKit

/// Custom NSTextView wrapper that sends on Enter, newline on Shift+Enter
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isEnabled: Bool
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ChatNSTextView()

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.onSend = onSend

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatNSTextView else { return }

        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEnabled
        textView.onSend = onSend

        // Placeholder
        if text.isEmpty && !textView.isFirstResponder {
            textView.placeholderString = placeholder
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextEditor

        init(_ parent: ChatTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

class ChatNSTextView: NSTextView {
    var onSend: (() -> Void)?
    var placeholderString: String?

    override func keyDown(with event: NSEvent) {
        // Enter without Shift = send
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }

    var isFirstResponder: Bool {
        window?.firstResponder == self
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let inset = textContainerInset
            let rect = NSRect(x: inset.width + 5, y: inset.height, width: bounds.width - inset.width * 2, height: bounds.height)
            placeholder.draw(in: rect, withAttributes: attrs)
        }
    }
}

// MARK: - PromptView

struct PromptView: View {
    let sessionID: UUID
    @EnvironmentObject var sessionManager: SessionManager
    @State private var promptText = ""

    private var session: Session? {
        sessionManager.sessions.first(where: { $0.id == sessionID })
    }

    private var isProcessing: Bool {
        session?.status == .running
    }

    var body: some View {
        VStack(spacing: 0) {
            // Processing indicator
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)

                    Text("Claude is working...")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        sessionManager.stopSession(sessionID)
                    } label: {
                        Text("Stop")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.05))

                Divider()
            }

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                // Text input container
                VStack(spacing: 0) {
                    ChatTextEditor(
                        text: $promptText,
                        placeholder: isProcessing ? "Wait for Claude to finish..." : "Message Claude... (Enter to send, Shift+Enter for new line)",
                        isEnabled: !isProcessing,
                        onSend: { sendMessage() }
                    )
                    .frame(minHeight: 36, maxHeight: 120)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor.opacity(isProcessing ? 0 : 0.3), lineWidth: 1)
                )

                // Send button
                VStack {
                    Spacer(minLength: 0)

                    if isProcessing {
                        Button {
                            sessionManager.stopSession(sessionID)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 32, height: 32)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white)
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop (Esc)")
                    } else {
                        Button {
                            sendMessage()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .help("Send (Enter)")
                    }
                }
                .frame(height: 36)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing
    }

    private func sendMessage() {
        let message = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isProcessing else { return }

        sessionManager.sendMessage(to: sessionID, message: message)
        promptText = ""
    }
}

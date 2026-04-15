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
    @Environment(\.colorScheme) private var colorScheme

    private var session: Session? {
        sessionManager.sessions.first(where: { $0.id == sessionID })
    }

    private var isProcessing: Bool {
        session?.status == .running
    }

    private var sessionError: SessionSendError? {
        sessionManager.sessionErrors[sessionID]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Error recovery banner
            if let error = sessionError {
                errorBanner(error)
                Divider()
            }

            // Processing indicator
            if isProcessing {
                HStack(spacing: Spacing.sm) {
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
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                            Text("Stop")
                                .font(.caption)
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.04))
                )

                Divider()
            }

            // Input area
            HStack(alignment: .bottom, spacing: 10) {
                // Text input container
                ChatTextEditor(
                    text: $promptText,
                    placeholder: isProcessing
                        ? "Wait for Claude to finish..."
                        : "Message Claude... (Enter to send, Shift+Enter for new line)",
                    isEnabled: !isProcessing,
                    onSend: { sendMessage() }
                )
                .frame(minHeight: 36, maxHeight: 120)
                .padding(.horizontal, 4)

                .glassBackground(cornerRadius: CornerRadius.md, shadow: false)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .strokeBorder(
                            isProcessing
                                ? Color.clear
                                : Color.accentColor.opacity(colorScheme == .light ? 0.15 : 0.2),
                            lineWidth: 0.5
                        )
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
                        .help("Stop (Cmd+.)")
                    } else {
                        Button {
                            sendMessage()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(canSend ? Color.accentColor : Color.secondary.opacity(0.2))
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
        .onAppear {
            // Restore preserved draft if any
            if let draft = sessionManager.consumePreservedDraft(sessionID) {
                promptText = draft
            }
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

    // MARK: - Error Recovery Banner

    @ViewBuilder
    private func errorBanner(_ error: SessionSendError) -> some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(error.userMessage)
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(.primary)

                    if let desc = error.errorDescription, desc != error.userMessage {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Dismiss button
                Button {
                    sessionManager.dismissError(sessionID)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .background(.quaternary.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Recovery action buttons
            HStack(spacing: Spacing.md) {
                if error.shouldRecreateSession {
                    Button {
                        sessionManager.recreateSession(sessionID)
                    } label: {
                        Label("New Session", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if error.isRetryable {
                    Button {
                        sessionManager.retryLastMessage(sessionID)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(.orange.opacity(0.06))
        .overlay(
            Rectangle()
                .fill(.orange.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

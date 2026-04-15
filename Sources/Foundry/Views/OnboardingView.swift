import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.orange.opacity(0.08))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            // Title
            VStack(spacing: 8) {
                Text("Claude Code Not Found")
                    .font(.title.bold())

                Text("Foundry requires Claude Code CLI to be installed on your system.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Installation instructions
            VStack(alignment: .leading, spacing: 16) {
                Text("Installation Steps")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    instructionStep(number: 1, text: "Install Claude Code via npm:")
                    codeBlock("npm install -g @anthropic-ai/claude-code")

                    instructionStep(number: 2, text: "Or install directly:")
                    codeBlock("curl -fsSL https://claude.ai/install.sh | sh")

                    instructionStep(number: 3, text: "Verify installation:")
                    codeBlock("claude --version")
                }
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .frame(maxWidth: 500)

            // Retry button
            Button {
                isChecking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    sessionManager.checkClaudeAvailability()
                    isChecking = false
                }
            } label: {
                if isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 180)
                } else {
                    Label("Check Again", systemImage: "arrow.clockwise")
                        .frame(width: 180)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isChecking)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, alignment: .trailing)

            Text(text)
                .font(.body)
        }
    }

    private func codeBlock(_ code: String) -> some View {
        HStack {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 32)
    }
}

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var isChecking = false
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous)
                    .fill(GradientTokens.warm.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .shadow(color: .orange.opacity(0.15), radius: 20, y: 4)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(GradientTokens.warm)
            }

            // Title
            VStack(spacing: Spacing.sm) {
                Text("Claude Code Not Found")
                    .font(.title.bold())

                Text("Foundry requires Claude Code CLI to be installed on your system.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Installation instructions
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Installation Steps")
                    .font(.headline)

                VStack(alignment: .leading, spacing: Spacing.md) {
                    instructionStep(number: 1, text: "Install Claude Code via npm:")
                    codeBlock("npm install -g @anthropic-ai/claude-code")

                    instructionStep(number: 2, text: "Or install directly:")
                    codeBlock("curl -fsSL https://claude.ai/install.sh | sh")

                    instructionStep(number: 3, text: "Verify installation:")
                    codeBlock("claude --version")
                }
            }
            .padding(Spacing.xl)
            .glassCard(cornerRadius: CornerRadius.lg)
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
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 16)
        .animation(FoundryAnimation.gentle, value: isVisible)
        .onAppear { isVisible = true }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
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
        .padding(Spacing.md)
        .glassBackground(cornerRadius: CornerRadius.sm, shadow: false)
        .padding(.leading, Spacing.xxl)
    }
}

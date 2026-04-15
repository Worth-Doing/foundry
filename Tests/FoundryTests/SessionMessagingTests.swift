// SessionMessagingTests.swift
// Tests for session messaging reliability in Foundry
//
// NOTE: Requires Xcode.app (not just Command Line Tools) for XCTest.
// Run with: swift test --filter SessionMessagingTests
// Or: xcodebuild test -scheme Foundry
//
// If using Command Line Tools only, run the validation script instead:
//   swift Tests/FoundryTests/ValidateSessionMessaging.swift

#if canImport(XCTest)
import XCTest
@testable import Foundry

final class SessionMessagingTests: XCTestCase {

    // MARK: - Exit Code Mapping Tests

    func testExitCode127MapsToCommandNotFound() {
        let error = mapExitCode(127, stderr: "claude: command not found", isResume: false)
        if case .exitCommandNotFound = error { } else {
            XCTFail("Expected .exitCommandNotFound, got \(error)")
        }
    }

    func testExitCode127WithNodeMapsToNodeNotFound() {
        let error = mapExitCode(127, stderr: "node: command not found", isResume: false)
        if case .nodeNotFound = error { } else {
            XCTFail("Expected .nodeNotFound, got \(error)")
        }
    }

    func testExitCode1ResumeMapsToSessionInvalid() {
        let error = mapExitCode(1, stderr: "Error: session not found", isResume: true)
        if case .exitSessionInvalid = error { } else {
            XCTFail("Expected .exitSessionInvalid, got \(error)")
        }
    }

    func testExitCode1NonResumeDoesNotMapToSessionInvalid() {
        let error = mapExitCode(1, stderr: "Error: session not found", isResume: false)
        if case .exitSessionInvalid = error {
            XCTFail("Non-resume should not be .exitSessionInvalid")
        }
    }

    func testExitCode1GenericMapsToRuntimeError() {
        let error = mapExitCode(1, stderr: "unexpected error", isResume: false)
        if case .exitRuntimeError(let code, _) = error {
            XCTAssertEqual(code, 1)
        } else {
            XCTFail("Expected .exitRuntimeError, got \(error)")
        }
    }

    func testExitCode126MapsToPermissionDenied() {
        let error = mapExitCode(126, stderr: "permission denied", isResume: false)
        if case .processStartFailed = error { } else {
            XCTFail("Expected .processStartFailed, got \(error)")
        }
    }

    // MARK: - Error Property Tests

    func testSessionInvalidShouldRecreate() {
        let error = SessionSendError.exitSessionInvalid(stderr: "test")
        XCTAssertTrue(error.shouldRecreateSession)
        XCTAssertFalse(error.isRetryable)
    }

    func testSessionBusyIsRetryable() {
        let error = SessionSendError.sessionBusy
        XCTAssertTrue(error.isRetryable)
        XCTAssertFalse(error.shouldRecreateSession)
    }

    func testClaudeNotFoundIsTerminal() {
        let error = SessionSendError.claudeNotFound
        XCTAssertFalse(error.isRetryable)
        XCTAssertFalse(error.shouldRecreateSession)
    }

    // MARK: - Preflight Validation Tests

    func testPreflightRejectsNonexistentPath() {
        let result = SessionPreflight.validate(
            projectPath: "/nonexistent/\(UUID().uuidString)",
            claudeSessionID: nil,
            isRunning: false
        )
        XCTAssertFalse(result.isValid)
        if case .invalidProjectPath = result.error { } else {
            XCTFail("Expected .invalidProjectPath")
        }
    }

    func testPreflightRejectsBusy() {
        let result = SessionPreflight.validate(
            projectPath: NSTemporaryDirectory(),
            claudeSessionID: nil,
            isRunning: true
        )
        XCTAssertFalse(result.isValid)
        if case .sessionBusy = result.error { } else {
            XCTFail("Expected .sessionBusy")
        }
    }

    func testPreflightAcceptsValidPath() {
        let result = SessionPreflight.validate(
            projectPath: NSTemporaryDirectory(),
            claudeSessionID: nil,
            isRunning: false
        )
        if case .invalidProjectPath = result.error {
            XCTFail("Valid temp dir should pass path validation")
        }
    }

    // MARK: - Environment Resolution Tests

    func testEnvironmentResolvesPath() {
        let env = ShellEnvironmentResolver.shared.resolvedEnvironment()
        XCTAssertNotNil(env["PATH"])
        XCTAssertTrue(env["PATH"]?.contains("/usr/bin") ?? false)
    }

    func testEnvironmentCaching() {
        let env1 = ShellEnvironmentResolver.shared.resolvedEnvironment()
        let env2 = ShellEnvironmentResolver.shared.resolvedEnvironment()
        XCTAssertEqual(env1["PATH"], env2["PATH"])
    }

    // MARK: - FindClaudePath Tests

    func testFindClaudeInCustomPath() throws {
        let tempDir = NSTemporaryDirectory() + "foundry-test-\(UUID().uuidString)"
        let claudePath = tempDir + "/claude"

        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try "#!/bin/sh\necho test".write(toFile: claudePath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claudePath)

        let found = ClaudeProcessController.findClaudePath(environment: ["PATH": tempDir])
        XCTAssertEqual(found, claudePath)
    }

    func testFindClaudeWithEmptyPath() {
        _ = ClaudeProcessController.findClaudePath(environment: ["PATH": ""])
        // No crash = pass
    }

    // MARK: - Error Message Quality

    func testAllErrorsHaveDistinctMessages() {
        let messages = [
            SessionSendError.claudeNotFound.userMessage,
            SessionSendError.nodeNotFound.userMessage,
            SessionSendError.sessionBusy.userMessage,
            SessionSendError.exitCommandNotFound(stderr: "").userMessage,
            SessionSendError.exitSessionInvalid(stderr: "").userMessage,
            SessionSendError.invalidProjectPath("").userMessage,
        ]
        let unique = Set(messages)
        XCTAssertEqual(unique.count, messages.count, "Each error type needs a distinct user message")
    }

    // MARK: - Helper

    private func mapExitCode(
        _ code: Int32,
        stderr: String,
        isResume: Bool,
        sessionID: String? = nil
    ) -> SessionSendError {
        let stderrLower = stderr.lowercased()
        switch code {
        case 127:
            if stderrLower.contains("node") || stderrLower.contains("npm") { return .nodeNotFound }
            return .exitCommandNotFound(stderr: stderr)
        case 1:
            if isResume {
                if stderrLower.contains("session") && (stderrLower.contains("not found") || stderrLower.contains("invalid") || stderrLower.contains("expired")) {
                    return .exitSessionInvalid(stderr: stderr)
                }
                if stderrLower.contains("no such session") || stderrLower.contains("could not find session") || stderrLower.contains("does not exist") {
                    return .exitSessionInvalid(stderr: stderr)
                }
                if stderrLower.contains("resume") && stderrLower.contains("error") {
                    return .exitSessionInvalid(stderr: stderr)
                }
            }
            if stderrLower.contains("not found") || stderrLower.contains("no such file") {
                return .exitCommandNotFound(stderr: stderr)
            }
            return .exitRuntimeError(code: code, stderr: stderr)
        case 126:
            return .processStartFailed("Permission denied")
        default:
            return .exitRuntimeError(code: code, stderr: stderr)
        }
    }
}
#endif

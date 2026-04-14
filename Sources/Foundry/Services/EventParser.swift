import Foundation

/// Parses Claude Code stream-json output lines into structured SessionEvents
struct EventParser {

    /// Parse a single JSON line from Claude Code stream output
    static func parse(line: String) -> SessionEvent? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = line.data(using: .utf8) else { return nil }

        // Try structured JSON parsing first
        if let event = try? JSONDecoder().decode(ClaudeStreamEvent.self, from: data) {
            return convert(streamEvent: event, rawLine: line)
        }

        // Try generic JSON dictionary parsing
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return convertGeneric(json: json, rawLine: line)
        }

        // Fallback: treat as plain text message
        return SessionEvent(
            type: .assistantMessage,
            content: line
        )
    }

    /// Parse usage/cost info from a stream event
    static func parseUsage(from line: String) -> TokenUsage? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(ClaudeStreamEvent.self, from: data) else {
            return nil
        }

        guard let usage = event.usage else { return nil }

        var tokenUsage = TokenUsage()
        tokenUsage.inputTokens = usage.input_tokens ?? 0
        tokenUsage.outputTokens = usage.output_tokens ?? 0
        tokenUsage.cacheReadTokens = usage.cache_read_input_tokens ?? 0
        tokenUsage.cacheWriteTokens = usage.cache_creation_input_tokens ?? 0
        if let cost = event.cost_usd {
            tokenUsage.estimatedCostUSD = cost
        }
        return tokenUsage
    }

    // MARK: - Private conversion

    private static func convert(streamEvent: ClaudeStreamEvent, rawLine: String) -> SessionEvent? {
        let type = streamEvent.type

        switch type {
        case "system":
            let sessionId = streamEvent.session_id ?? ""
            return SessionEvent(
                type: .sessionStart,
                content: "Session started",
                metadata: EventMetadata(agentName: sessionId)
            )

        case "assistant":
            if let message = streamEvent.message,
               let content = message.content {
                // Process content blocks
                for block in content {
                    if block.type == "tool_use" {
                        let toolName = block.name ?? "unknown"
                        let inputStr = block.input?.stringValue ?? describeValue(block.input?.value)
                        return SessionEvent(
                            type: .toolUse,
                            content: inputStr,
                            metadata: EventMetadata(toolName: toolName)
                        )
                    } else if block.type == "text" {
                        return SessionEvent(
                            type: .assistantMessage,
                            content: block.text ?? ""
                        )
                    } else if block.type == "thinking" {
                        return SessionEvent(
                            type: .thinking,
                            content: block.text ?? ""
                        )
                    }
                }
            }
            // Delta handling for streaming
            if let delta = streamEvent.delta {
                if delta.type == "text_delta" {
                    return SessionEvent(
                        type: .assistantMessage,
                        content: delta.text ?? ""
                    )
                }
            }
            if let block = streamEvent.content_block {
                if block.type == "tool_use" {
                    return SessionEvent(
                        type: .toolUse,
                        content: "",
                        metadata: EventMetadata(toolName: block.name ?? "unknown")
                    )
                } else if block.type == "text" {
                    return SessionEvent(
                        type: .assistantMessage,
                        content: block.text ?? ""
                    )
                } else if block.type == "thinking" {
                    return SessionEvent(
                        type: .thinking,
                        content: block.text ?? ""
                    )
                }
            }
            return nil

        case "content_block_start":
            if let block = streamEvent.content_block {
                if block.type == "tool_use" {
                    return SessionEvent(
                        type: .toolUse,
                        content: "",
                        metadata: EventMetadata(toolName: block.name ?? "unknown")
                    )
                } else if block.type == "thinking" {
                    return SessionEvent(type: .thinking, content: "")
                }
            }
            return nil

        case "content_block_delta":
            if let delta = streamEvent.delta {
                if delta.type == "text_delta" || delta.type == "thinking_delta" {
                    let eventType: EventType = delta.type == "thinking_delta" ? .thinking : .assistantMessage
                    return SessionEvent(type: eventType, content: delta.text ?? "")
                } else if delta.type == "input_json_delta" {
                    return nil // Accumulate tool input deltas
                }
            }
            return nil

        case "content_block_stop":
            return nil

        case "message_start":
            return nil

        case "message_delta", "message_stop":
            if let usage = streamEvent.usage {
                return SessionEvent(
                    type: .costUpdate,
                    content: "",
                    metadata: EventMetadata(
                        inputTokens: usage.input_tokens,
                        outputTokens: usage.output_tokens
                    )
                )
            }
            return nil

        case "result":
            if streamEvent.is_error == true {
                return SessionEvent(
                    type: .error,
                    content: streamEvent.error ?? "Unknown error"
                )
            }
            let costStr = streamEvent.cost_usd.map { String(format: "$%.4f", $0) } ?? ""
            return SessionEvent(
                type: .costUpdate,
                content: costStr,
                metadata: EventMetadata(
                    inputTokens: streamEvent.usage?.input_tokens,
                    outputTokens: streamEvent.usage?.output_tokens,
                    costUSD: streamEvent.cost_usd
                )
            )

        default:
            return nil
        }
    }

    private static func convertGeneric(json: [String: Any], rawLine: String) -> SessionEvent? {
        guard let type = json["type"] as? String else {
            return SessionEvent(type: .systemInfo, content: rawLine)
        }

        switch type {
        case "error":
            let msg = json["error"] as? String ?? json["message"] as? String ?? rawLine
            return SessionEvent(type: .error, content: msg)

        case "tool_use", "tool_call":
            let name = json["name"] as? String ?? json["tool_name"] as? String ?? "unknown"
            let input = json["input"] as? String ?? ""
            return SessionEvent(
                type: .toolUse,
                content: input,
                metadata: EventMetadata(toolName: name)
            )

        case "tool_result":
            let content = json["content"] as? String ?? json["output"] as? String ?? ""
            return SessionEvent(type: .toolResult, content: content)

        default:
            return nil
        }
    }

    private static func describeValue(_ value: AnyCodableValue?) -> String {
        guard let value = value else { return "" }
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array: return "[...]"
        case .dictionary(let d):
            let pairs = d.prefix(3).map { "\($0.key): ..." }
            return "{\(pairs.joined(separator: ", "))}"
        }
    }
}

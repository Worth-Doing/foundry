import Foundation

struct SessionEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let type: EventType
    var content: String
    var metadata: EventMetadata?
    var isExpanded: Bool

    init(
        type: EventType,
        content: String,
        metadata: EventMetadata? = nil,
        isExpanded: Bool = true
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.type = type
        self.content = content
        self.metadata = metadata
        self.isExpanded = isExpanded
    }
}

enum EventType: String, Codable, Sendable {
    case userInput
    case assistantMessage
    case toolUse
    case toolResult
    case fileRead
    case fileWrite
    case fileEdit
    case bashCommand
    case bashOutput
    case search
    case subAgentSpawn
    case subAgentResult
    case error
    case permissionRequest
    case permissionResponse
    case thinking
    case costUpdate
    case sessionStart
    case sessionEnd
    case systemInfo
}

struct EventMetadata: Codable, Sendable {
    var toolName: String?
    var filePath: String?
    var command: String?
    var exitCode: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var costUSD: Double?
    var agentName: String?
    var searchPattern: String?
    var diffContent: String?
}

// MARK: - Stream JSON models for parsing Claude Code output

struct ClaudeStreamEvent: Codable, Sendable {
    let type: String
    let subtype: String?
    let session_id: String?
    // Assistant message fields
    let message: ClaudeMessage?
    // Tool use fields
    let tool_name: String?
    let tool_input: AnyCodable?
    // Result fields
    let result: AnyCodable?
    let error: String?
    // Content delta
    let content_block: ClaudeContentBlock?
    let delta: ClaudeDelta?
    let index: Int?
    // Usage
    let usage: ClaudeUsage?
    // Cost
    let cost_usd: Double?
    let duration_ms: Double?
    let duration_api_ms: Double?
    let num_turns: Int?
    let is_error: Bool?
}

struct ClaudeMessage: Codable, Sendable {
    let id: String?
    let role: String?
    let content: [ClaudeContentBlock]?
    let model: String?
    let usage: ClaudeUsage?
}

struct ClaudeContentBlock: Codable, Sendable {
    let type: String?
    let text: String?
    let name: String?
    let input: AnyCodable?
    let id: String?
    let content: AnyCodable?
}

struct ClaudeDelta: Codable, Sendable {
    let type: String?
    let text: String?
}

struct ClaudeUsage: Codable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

// A type-erased Codable wrapper for dynamic JSON values
struct AnyCodable: Codable, Sendable {
    let value: AnyCodableValue

    init(_ value: Any) {
        self.value = AnyCodable.wrap(value)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = .null
        } else if let bool = try? container.decode(Bool.self) {
            self.value = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = .double(double)
        } else if let string = try? container.decode(String.self) {
            self.value = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = .array(array.map(\.value))
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = .dictionary(dict.mapValues(\.value))
        } else {
            self.value = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v.map { AnyCodable(fromValue: $0) })
        case .dictionary(let v): try container.encode(v.mapValues { AnyCodable(fromValue: $0) })
        }
    }

    init(fromValue val: AnyCodableValue) {
        self.value = val
    }

    private static func wrap(_ value: Any) -> AnyCodableValue {
        switch value {
        case let v as String: return .string(v)
        case let v as Int: return .int(v)
        case let v as Double: return .double(v)
        case let v as Bool: return .bool(v)
        default: return .null
        }
    }

    var stringValue: String? {
        if case .string(let s) = value { return s }
        return nil
    }

    var dictValue: [String: AnyCodableValue]? {
        if case .dictionary(let d) = value { return d }
        return nil
    }
}

enum AnyCodableValue: Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let wrapped = try AnyCodable(from: decoder)
        self = wrapped.value
    }

    func encode(to encoder: Encoder) throws {
        try AnyCodable(fromValue: self).encode(to: encoder)
    }
}

import Foundation

/// A single conversational message.
public struct AIMessage: Sendable, Codable, Hashable {
    public let role: AIRole
    public let content: [AIContent]

    public init(role: AIRole, content: [AIContent]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)])
    }
}

/// A provider-neutral message role.
public enum AIRole: String, Sendable, Codable, Hashable {
    case user
    case assistant
}

/// A message content block.
public enum AIContent: Sendable, Codable, Hashable {
    case text(String)
    case image(AIImage)
    case document(AIDocument)
}

/// A basic image payload.
public struct AIImage: Sendable, Codable, Hashable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String) {
        self.data = data
        self.mediaType = mediaType
    }
}

/// A basic document payload.
public struct AIDocument: Sendable, Codable, Hashable {
    public let data: Data
    public let mediaType: String
    public let filename: String?

    public init(data: Data, mediaType: String, filename: String? = nil) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
    }
}

import Foundation

/// A single conversational message.
public struct AIMessage: Sendable, Codable, Equatable {
    public let role: AIRole
    public let content: [AIContent]

    public init(role: AIRole, content: [AIContent]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func user(_ content: [AIContent]) -> AIMessage {
        AIMessage(role: .user, content: content)
    }

    public static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: [.text(text)])
    }

    public static func assistant(_ content: [AIContent]) -> AIMessage {
        AIMessage(role: .assistant, content: content)
    }

    public static func tool(id: String, content: String) -> AIMessage {
        AIMessage(
            role: .tool,
            content: [.toolResult(AIToolResult(toolUseId: id, content: content))]
        )
    }
}

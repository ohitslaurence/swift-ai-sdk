import Foundation

/// A tool definition the model may call.
public struct AITool: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: AIJSONSchema
    public let handler: @Sendable (Data) async throws -> String
    public let needsApproval: Bool

    public init(
        name: String,
        description: String,
        inputSchema: AIJSONSchema,
        needsApproval: Bool = false,
        handler: @escaping @Sendable (Data) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
        self.needsApproval = needsApproval
    }
}

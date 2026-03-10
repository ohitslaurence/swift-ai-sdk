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

    /// Create a tool with typed `AIStructured` input and `Encodable` output.
    ///
    /// Derives `inputSchema` from `Input.jsonSchema`. JSON-encodes non-`String` outputs.
    /// The stored handler remains `Data -> String` for provider-independent execution.
    public static func define<Input: AIStructured, Output: Encodable & Sendable>(
        name: String,
        description: String,
        needsApproval: Bool = false,
        handler: @escaping @Sendable (Input) async throws -> Output
    ) throws -> AITool {
        let schema = try Input.jsonSchema

        return AITool(
            name: name,
            description: description,
            inputSchema: schema,
            needsApproval: needsApproval
        ) { data in
            let decoder = JSONDecoder()
            let input = try decoder.decode(Input.self, from: data)
            let output = try await handler(input)

            if let stringOutput = output as? String {
                return stringOutput
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let outputData = try encoder.encode(output)
            return String(data: outputData, encoding: .utf8) ?? ""
        }
    }
}

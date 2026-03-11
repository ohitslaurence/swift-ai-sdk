import Foundation

package struct AIToolInputDecodingError: Error, Sendable {
    package let context: AIErrorContext

    package init(_ error: any Error) {
        self.context = AIErrorContext(error)
    }
}

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
            let input: Input

            do {
                input = try JSONDecoder().decode(Input.self, from: data)
            } catch is CancellationError {
                throw AIError.cancelled
            } catch {
                throw AIToolInputDecodingError(error)
            }

            let output = try await handler(input)

            if let stringOutput = output as? String {
                return stringOutput
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let outputData = try encoder.encode(output)
            return String(decoding: outputData, as: UTF8.self)
        }
    }
}

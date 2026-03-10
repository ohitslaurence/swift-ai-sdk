import Foundation

/// The core structured output engine.
///
/// Selects a strategy from `provider.capabilities.structuredOutput`, issues requests,
/// and handles the decode → repair → retry flow.
enum StructuredOutputGenerator {

    /// Generate a structured response from a provider.
    static func generate<T: AIStructured>(
        provider: any AIProvider,
        request: AIRequest,
        schema: T.Type,
        maxRetries: Int,
        repair: AIRepairHandler?
    ) async throws -> AIStructuredResponse<T> {
        let jsonSchema = try T.jsonSchema
        let strategy = selectStrategy(capabilities: provider.capabilities.structuredOutput)
        var currentRequest = applyStrategy(
            strategy,
            to: request,
            schema: jsonSchema,
            schemaName: T.schemaName,
            capabilities: provider.capabilities
        )

        for attempt in 1...(maxRetries + 1) {
            try checkCancellation()

            let response = try await provider.complete(currentRequest)
            let rawText = extractText(from: response, strategy: strategy)

            // Step 1: Try direct decode.
            if let value = tryDecode(rawText, as: T.self) {
                return AIStructuredResponse(value: value, response: response, attempts: attempt)
            }

            // Step 2: Try built-in repair.
            try checkCancellation()

            if let repaired = StructuredOutputRepair.attemptBuiltInRepair(rawText),
                let value = tryDecode(repaired, as: T.self)
            {
                return AIStructuredResponse(value: value, response: response, attempts: attempt)
            }

            // Step 3: Try custom repair handler.
            if let repair {
                try checkCancellation()

                let errorContext = decodingErrorContext(rawText, as: T.self)
                if let customRepaired = try await repair(rawText, errorContext),
                    let value = tryDecode(customRepaired, as: T.self)
                {
                    return AIStructuredResponse(
                        value: value, response: response, attempts: attempt
                    )
                }
            }

            // Step 4: If retries remain, append corrective context and try again.
            let isLastAttempt = attempt > maxRetries
            if isLastAttempt {
                let errorContext = decodingErrorContext(rawText, as: T.self)
                throw AIError.decodingError(
                    AIErrorContext(
                        message:
                            "Failed to decode \(T.self) after \(attempt) attempt(s): \(errorContext.message)"
                    )
                )
            }

            try checkCancellation()

            let errorContext = decodingErrorContext(rawText, as: T.self)
            let retryInstruction = StructuredOutputRepair.retryPrompt(error: errorContext.message)
            let existingSystem = currentRequest.systemPrompt ?? ""
            currentRequest.systemPrompt =
                existingSystem.isEmpty
                ? retryInstruction
                : existingSystem + "\n\n" + retryInstruction
        }

        throw AIError.decodingError(
            AIErrorContext(message: "Unexpected exit from structured output retry loop")
        )
    }

    // MARK: - Strategy Selection

    enum Strategy: Sendable, Equatable {
        case nativeJSONSchema
        case nativeJSONMode
        case toolCallFallback
        case promptInjection
    }

    static func selectStrategy(
        capabilities: AIStructuredOutputCapabilities
    ) -> Strategy {
        if capabilities.supportsJSONSchema {
            return .nativeJSONSchema
        }

        switch capabilities.defaultStrategy {
        case .providerNative:
            if capabilities.supportsJSONMode {
                return .nativeJSONMode
            }
            return .promptInjection

        case .toolCallFallback:
            return .toolCallFallback

        case .promptInjection:
            return .promptInjection
        }
    }

    // MARK: - Strategy Application

    private static func applyStrategy(
        _ strategy: Strategy,
        to request: AIRequest,
        schema: AIJSONSchema,
        schemaName: String,
        capabilities: AIProviderCapabilities
    ) -> AIRequest {
        var modified = request

        switch strategy {
        case .nativeJSONSchema:
            modified.responseFormat = .jsonSchema(schema)

        case .nativeJSONMode:
            modified.responseFormat = .json

        case .toolCallFallback:
            let tool = AITool(
                name: "_structured_output",
                description: "Return the structured output matching the schema for \(schemaName).",
                inputSchema: schema
            ) { _ in "" }

            modified.tools = [tool]
            if capabilities.tools.supportsForcedToolChoice {
                modified.toolChoice = .tool("_structured_output")
            } else {
                let instruction =
                    "You must call the _structured_output tool with JSON matching the provided schema."
                let existing = modified.systemPrompt ?? ""
                modified.systemPrompt =
                    existing.isEmpty ? instruction : existing + "\n\n" + instruction
            }

        case .promptInjection:
            let schemaJSON = schemaToJSONString(schema)
            let instruction =
                "You must respond with ONLY valid JSON matching this schema:\n\(schemaJSON)\n"
                + "Do not include any text before or after the JSON."
            let existing = modified.systemPrompt ?? ""
            modified.systemPrompt =
                existing.isEmpty ? instruction : existing + "\n\n" + instruction
        }

        return modified
    }

    // MARK: - Text Extraction

    private static func extractText(
        from response: AIResponse,
        strategy: Strategy
    ) -> String {
        if strategy == .toolCallFallback {
            for content in response.content {
                if case .toolUse(let toolUse) = content, toolUse.name == "_structured_output" {
                    return String(data: toolUse.input, encoding: .utf8) ?? ""
                }
            }
        }

        return response.text
    }

    // MARK: - Decode Helpers

    private static func tryDecode<T: Codable>(_ text: String, as type: T.Type) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func decodingErrorContext<T: Codable>(
        _ text: String, as type: T.Type
    ) -> AIErrorContext {
        guard let data = text.data(using: .utf8) else {
            return AIErrorContext(message: "Text is not valid UTF-8")
        }
        do {
            _ = try JSONDecoder().decode(type, from: data)
            return AIErrorContext(message: "Unknown decoding error")
        } catch {
            return AIErrorContext(message: error.localizedDescription)
        }
    }

    private static func schemaToJSONString(_ schema: AIJSONSchema) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schema),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return string
    }

    private static func checkCancellation() throws {
        if Task.isCancelled {
            throw AIError.cancelled
        }
    }
}

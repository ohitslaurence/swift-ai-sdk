extension AIProvider {
    /// Generate a structured response decoded into an `AIStructured` type.
    public func generate<T: AIStructured>(
        _ prompt: String,
        schema: T.Type,
        model: AIModel,
        systemPrompt: String? = nil,
        maxRetries: Int = 2,
        repair: AIRepairHandler? = nil
    ) async throws -> AIStructuredResponse<T> {
        let request = AIRequest(
            model: model,
            messages: [.user(prompt)],
            systemPrompt: systemPrompt
        )

        return try await StructuredOutputGenerator.generate(
            provider: self,
            request: request,
            schema: schema,
            maxRetries: maxRetries,
            repair: repair
        )
    }

    /// Generate a structured response from a full request.
    public func generate<T: AIStructured>(
        _ request: AIRequest,
        schema: T.Type,
        maxRetries: Int = 2,
        repair: AIRepairHandler? = nil
    ) async throws -> AIStructuredResponse<T> {
        try await StructuredOutputGenerator.generate(
            provider: self,
            request: request,
            schema: schema,
            maxRetries: maxRetries,
            repair: repair
        )
    }
}

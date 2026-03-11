/// Controls how much detail is captured for a sensitive field.
public enum AITelemetryCaptureMode: Sendable {
    /// Remove the field entirely.
    case none
    /// Keep structure and counts but not full payload.
    case summary
    /// Preserve the full value.
    case full
}

/// Controls which fields are redacted before telemetry events are emitted.
public struct AITelemetryRedaction: Sendable {
    public var prompts: AITelemetryCaptureMode
    public var responses: AITelemetryCaptureMode
    public var toolArguments: AITelemetryCaptureMode
    public var toolResults: AITelemetryCaptureMode
    public var embeddingInputs: AITelemetryCaptureMode
    public var embeddingVectors: AITelemetryCaptureMode
    public var allowedHeaderNames: Set<String>

    public static let `default` = AITelemetryRedaction()

    public init(
        prompts: AITelemetryCaptureMode = .summary,
        responses: AITelemetryCaptureMode = .summary,
        toolArguments: AITelemetryCaptureMode = .summary,
        toolResults: AITelemetryCaptureMode = .summary,
        embeddingInputs: AITelemetryCaptureMode = .summary,
        embeddingVectors: AITelemetryCaptureMode = .none,
        allowedHeaderNames: Set<String> = []
    ) {
        self.prompts = prompts
        self.responses = responses
        self.toolArguments = toolArguments
        self.toolResults = toolResults
        self.embeddingInputs = embeddingInputs
        self.embeddingVectors = embeddingVectors
        self.allowedHeaderNames = allowedHeaderNames
    }
}

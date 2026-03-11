import Foundation

/// A structured telemetry event emitted by the observability layer.
public struct AITelemetryEvent: Sendable {
    public let timestamp: Date
    public let operationID: String
    public let parentOperationID: String?
    public let operationKind: AIOperationKind
    public let kind: AITelemetryEventKind

    public init(
        timestamp: Date,
        operationID: String,
        parentOperationID: String? = nil,
        operationKind: AIOperationKind,
        kind: AITelemetryEventKind
    ) {
        self.timestamp = timestamp
        self.operationID = operationID
        self.parentOperationID = parentOperationID
        self.operationKind = operationKind
        self.kind = kind
    }
}

/// The kind of AI operation being observed.
public enum AIOperationKind: String, Sendable {
    case completion
    case stream
    case structuredOutput
    case toolLoop
    case embedding
}

/// The specific event within an operation's lifecycle.
public enum AITelemetryEventKind: Sendable {
    case requestStarted(AIGenerationRequestSnapshot, attempt: Int)
    case responseReceived(AIResponseSnapshot)
    case requestFailed(error: AIError, attempt: Int, metrics: AITelemetryMetrics?)
    case streamEvent(AIStreamEvent)
    case streamCompleted(finishReason: AIFinishReason?, metrics: AITelemetryMetrics?, accounting: AIAccounting?)
    case retryScheduled(attempt: Int, delay: TimeInterval, error: AIError)
    case toolApprovalRequested(AIToolCallSnapshot)
    case toolExecutionStarted(AIToolCallSnapshot)
    case toolExecutionFinished(AIToolResultSnapshot)
    case toolStepComplete(
        stepIndex: Int,
        toolCalls: [AIToolCallSnapshot],
        toolResults: [AIToolResultSnapshot],
        metrics: AITelemetryMetrics?,
        accounting: AIAccounting?
    )
    case embeddingStarted(AIEmbeddingRequestSnapshot)
    case embeddingResponse(AIEmbeddingResponseSnapshot)
    case cancelled
}

// MARK: - Snapshot Types

/// An immutable, redacted snapshot of a generation request.
public struct AIGenerationRequestSnapshot: Sendable {
    public let model: AIModel
    public let systemPrompt: String?
    public let messages: [AIMessageSnapshot]
    public let toolNames: [String]
    public let toolChoice: AIToolChoice?
    public let allowParallelToolCalls: Bool?
    public let responseFormat: AIResponseFormatKind
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let stopSequences: [String]
    public let metadata: [String: String]
    public let headers: [String: String]
}

/// An immutable snapshot of a message.
public struct AIMessageSnapshot: Sendable {
    public let role: AIRole
    public let content: [AIContentSnapshot]
}

/// An immutable snapshot of a content block.
public struct AIContentSnapshot: Sendable {
    public let kind: AIContentKind
    public let text: String?
    public let mediaType: String?
    public let toolName: String?
    public let toolUseID: String?
}

/// The kind of content in a snapshot.
public enum AIContentKind: String, Sendable, Hashable {
    case text
    case image
    case document
    case toolUse
    case toolResult
}

/// The response format expressed as a simple kind.
public enum AIResponseFormatKind: String, Sendable {
    case text
    case json
    case jsonSchema
}

/// An immutable, redacted snapshot of a response.
public struct AIResponseSnapshot: Sendable {
    public let id: String
    public let model: String
    public let content: [AIContentSnapshot]
    public let finishReason: AIFinishReason
    public let warnings: [AIProviderWarning]
    public let metrics: AITelemetryMetrics?
    public let accounting: AIAccounting?
}

/// An immutable snapshot of a tool call.
public struct AIToolCallSnapshot: Sendable {
    public let id: String
    public let name: String
    public let inputJSON: String?
}

/// An immutable snapshot of a tool result.
public struct AIToolResultSnapshot: Sendable {
    public let toolUseID: String
    public let content: String?
    public let isError: Bool
}

/// An immutable, redacted snapshot of an embedding request.
public struct AIEmbeddingRequestSnapshot: Sendable {
    public let model: AIModel
    public let inputs: [AIEmbeddingInputSnapshot]
    public let dimensions: Int?
    public let headers: [String: String]
    public let batchIndex: Int?
    public let batchCount: Int?
}

/// An immutable snapshot of an embedding input.
public struct AIEmbeddingInputSnapshot: Sendable {
    public let kind: AIEmbeddingInputKind
    public let text: String?
}

/// An immutable, redacted snapshot of an embedding response.
public struct AIEmbeddingResponseSnapshot: Sendable {
    public let model: String
    public let embeddings: [AIEmbeddingVectorSnapshot]
    public let warnings: [AIProviderWarning]
    public let metrics: AITelemetryMetrics?
    public let accounting: AIAccounting?
    public let batchIndex: Int?
    public let batchCount: Int?
}

/// An immutable snapshot of a single embedding vector.
public struct AIEmbeddingVectorSnapshot: Sendable {
    public let index: Int
    public let dimensions: Int
    public let vector: [Float]?
}

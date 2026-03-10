/// A provider-neutral stream event.
public enum AIStreamEvent: Sendable, Equatable {
    case start(id: String, model: String)
    case delta(AIStreamDelta)
    case toolUseStart(id: String, name: String)
    case usage(AIUsage)
    case finish(AIFinishReason)
}

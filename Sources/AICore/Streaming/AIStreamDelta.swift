/// A streamed delta emitted by a provider.
public enum AIStreamDelta: Sendable, Equatable {
    case text(String)
    case toolInput(id: String, jsonDelta: String)
}

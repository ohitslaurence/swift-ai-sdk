/// Describes provider-level feature support used by higher-level helpers.
public struct AIProviderCapabilities: Sendable {
    public var supportsStreaming: Bool
    public var supportsEmbeddings: Bool

    public static let `default` = AIProviderCapabilities(
        supportsStreaming: true,
        supportsEmbeddings: false
    )

    public init(supportsStreaming: Bool, supportsEmbeddings: Bool) {
        self.supportsStreaming = supportsStreaming
        self.supportsEmbeddings = supportsEmbeddings
    }
}

/// Timing and count metrics for a telemetry-observed operation.
public struct AITelemetryMetrics: Sendable {
    public let totalDuration: Duration?
    public let firstEventLatency: Duration?
    public let retryCount: Int
    public let streamEventCount: Int
    public let toolCallCount: Int

    public init(
        totalDuration: Duration? = nil,
        firstEventLatency: Duration? = nil,
        retryCount: Int = 0,
        streamEventCount: Int = 0,
        toolCallCount: Int = 0
    ) {
        self.totalDuration = totalDuration
        self.firstEventLatency = firstEventLatency
        self.retryCount = retryCount
        self.streamEventCount = streamEventCount
        self.toolCallCount = toolCallCount
    }
}

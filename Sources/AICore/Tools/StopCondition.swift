/// A predicate that determines when the tool execution loop should stop.
///
/// Conditions use OR logic: the first matched condition stops the loop.
/// Matching a condition returns `StopReason.conditionMet(description)`, not an error.
public struct StopCondition: Sendable {
    public let description: String
    public let evaluate: @Sendable ([AIToolStep]) async -> Bool

    public init(
        description: String,
        evaluate: @escaping @Sendable ([AIToolStep]) async -> Bool
    ) {
        self.description = description
        self.evaluate = evaluate
    }

    /// Stop after `n` tool-using steps have completed.
    public static func maxSteps(_ n: Int) -> StopCondition {
        StopCondition(description: "Maximum steps reached (\(n))") { steps in
            steps.count >= n
        }
    }

    /// Stop when a tool with the given name has been called.
    public static func toolCalled(_ name: String) -> StopCondition {
        StopCondition(description: "Tool called: \(name)") { steps in
            steps.contains { step in
                step.toolCalls.contains { $0.name == name }
            }
        }
    }

    /// Stop when a custom predicate returns `true`.
    public static func custom(
        description: String,
        _ predicate: @escaping @Sendable ([AIToolStep]) async -> Bool
    ) -> StopCondition {
        StopCondition(description: description, evaluate: predicate)
    }
}

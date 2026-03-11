/// Internal helper for aggregating usage across multiple responses.
package struct AIUsageAccumulator {
    package private(set) var inputTokens = 0
    package private(set) var outputTokens = 0
    package private(set) var cachedTokens: Int?
    package private(set) var cacheWriteTokens: Int?
    package private(set) var reasoningTokens: Int?
    package private(set) var hasValue = false

    package init() {}

    package mutating func add(_ usage: AIUsage?) {
        guard let usage else {
            return
        }

        hasValue = true
        inputTokens += usage.inputTokens
        outputTokens += usage.outputTokens

        if let cached = usage.inputTokenDetails?.cachedTokens {
            cachedTokens = (cachedTokens ?? 0) + cached
        }

        if let cacheWrites = usage.inputTokenDetails?.cacheWriteTokens {
            cacheWriteTokens = (cacheWriteTokens ?? 0) + cacheWrites
        }

        if let reasoning = usage.outputTokenDetails?.reasoningTokens {
            reasoningTokens = (reasoningTokens ?? 0) + reasoning
        }
    }

    package var value: AIUsage? {
        guard hasValue else {
            return nil
        }

        let inputDetails: AIUsage.InputTokenDetails? = {
            guard cachedTokens != nil || cacheWriteTokens != nil else {
                return nil
            }

            return AIUsage.InputTokenDetails(
                cachedTokens: cachedTokens,
                cacheWriteTokens: cacheWriteTokens
            )
        }()

        let outputDetails: AIUsage.OutputTokenDetails? = {
            guard reasoningTokens != nil else {
                return nil
            }

            return AIUsage.OutputTokenDetails(reasoningTokens: reasoningTokens)
        }()

        return AIUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            inputTokenDetails: inputDetails,
            outputTokenDetails: outputDetails
        )
    }
}

import Foundation

/// Exposes usage and optional provider-reported cost without hardcoding pricing tables.
public struct AIAccounting: Sendable {
    public let usage: AIUsage?
    public let providerReportedCost: AIReportedCost?

    public init(usage: AIUsage? = nil, providerReportedCost: AIReportedCost? = nil) {
        self.usage = usage
        self.providerReportedCost = providerReportedCost
    }
}

/// An authoritative cost figure reported by a provider or middleware.
public struct AIReportedCost: Sendable {
    public let amount: Decimal
    public let currencyCode: String
    public let source: String?

    public init(amount: Decimal, currencyCode: String, source: String? = nil) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.source = source
    }
}

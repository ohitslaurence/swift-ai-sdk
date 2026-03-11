import Foundation

/// A handler that attempts to repair invalid JSON text before retrying.
public typealias AIRepairHandler =
    @Sendable (
        _ text: String,
        _ error: AIErrorContext
    ) async throws -> String?

/// A Codable type that can be used as a structured output target.
///
/// The default `jsonSchema` implementation auto-generates a schema for a supported subset
/// of Swift types using safe decode probing. It may throw `AIError.unsupportedFeature`
/// when the type cannot be safely reflected.
///
/// Supported shapes:
/// - Structs and nested structs with synthesized keyed `Codable`
/// - `String`, `Int`, `Double`, `Bool`, `Decimal`, `Date`
/// - `Optional<T>`
/// - `Array<T>`
/// - String-backed enums that also conform to `CaseIterable`
/// - `CodingKeys`
///
/// Unsupported shapes throw `AIError.unsupportedFeature`:
/// - Custom `init(from:)` / `encode(to:)` that change the serialized shape
/// - Recursive or self-referential object graphs
/// - Associated-value enums
/// - Property-wrapper-driven serialization
/// - Polymorphic / discriminator-based decoding
public protocol AIStructured: Codable, Sendable {
    /// Stable schema name used by providers that require one.
    static var schemaName: String { get }

    /// JSON Schema for this type.
    static var jsonSchema: AIJSONSchema { get throws }
}

extension AIStructured {
    public static var schemaName: String {
        String(describing: Self.self)
    }

    public static var jsonSchema: AIJSONSchema {
        get throws {
            try AIJSONSchemaGenerator.generateSchema(for: Self.self)
        }
    }
}

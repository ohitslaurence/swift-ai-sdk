import Foundation

/// Generates `AIJSONSchema` from `Codable` types using Swift's Mirror-based reflection.
///
/// This generator is intentionally conservative. It supports a documented subset of Swift types
/// and throws `AIError.unsupportedFeature` for shapes that cannot be safely reflected.
enum AIJSONSchemaGenerator {

    /// Generate a JSON schema for the given `Codable` type.
    static func generateSchema(for type: any Codable.Type) throws -> AIJSONSchema {
        try schemaForType(type, visited: [])
    }

    private static func schemaForType(
        _ type: Any.Type,
        visited: Set<ObjectIdentifier>
    ) throws -> AIJSONSchema {
        let typeID = ObjectIdentifier(type)
        if visited.contains(typeID) {
            throw AIError.unsupportedFeature(
                "Recursive type detected: \(type). Provide a manual jsonSchema override."
            )
        }

        if type == String.self {
            return .string()
        }
        if type == Int.self || type == Int8.self || type == Int16.self
            || type == Int32.self || type == Int64.self
            || type == UInt.self || type == UInt8.self || type == UInt16.self
            || type == UInt32.self || type == UInt64.self
        {
            return .integer()
        }
        if type == Double.self || type == Float.self {
            return .number()
        }
        if type == Bool.self {
            return .boolean()
        }
        if type == Date.self {
            return .string(format: "date-time")
        }

        if let decimalType = type as? Decimal.Type {
            _ = decimalType
            return .number()
        }

        if let optionalType = type as? any OptionalProtocol.Type {
            return try schemaForType(optionalType.wrappedType, visited: visited)
        }

        if let arrayType = type as? any ArrayProtocol.Type {
            let itemSchema = try schemaForType(arrayType.elementType, visited: visited)
            return .array(items: itemSchema)
        }

        if let enumType = type as? any RawRepresentable.Type,
            type is any CaseIterable.Type
        {
            return try schemaForStringEnum(enumType)
        }

        let mirror = Mirror(reflecting: createDummyInstance(of: type))

        guard mirror.displayStyle == .struct || mirror.displayStyle == .class else {
            throw AIError.unsupportedFeature(
                "Unsupported type shape: \(type) (displayStyle: \(String(describing: mirror.displayStyle))). "
                    + "Only structs with synthesized Codable conformance are supported."
            )
        }

        guard !mirror.children.isEmpty else {
            throw AIError.unsupportedFeature(
                "Empty type \(type) cannot be reflected into a schema. Provide a manual jsonSchema override."
            )
        }

        let allChildrenAreLabeled = mirror.children.allSatisfy { $0.label != nil }
        guard allChildrenAreLabeled else {
            throw AIError.unsupportedFeature(
                "Type \(type) has unlabeled children (unkeyed container). "
                    + "Provide a manual jsonSchema override."
            )
        }

        let codingKeyMap = extractCodingKeys(for: type)

        var visitedWithSelf = visited
        visitedWithSelf.insert(typeID)

        var properties: [String: AIJSONSchema] = [:]
        var required: [String] = []

        for child in mirror.children {
            guard let label = child.label else { continue }
            let propertyName = cleanPropertyName(label)
            let externalName = codingKeyMap[propertyName] ?? propertyName
            let childType = Swift.type(of: child.value)

            let schema = try schemaForType(childType, visited: visitedWithSelf)
            properties[externalName] = schema

            if !(childType is any OptionalProtocol.Type) {
                required.append(externalName)
            }
        }

        return .object(properties: properties, required: required)
    }

    private static func schemaForStringEnum(
        _ type: any RawRepresentable.Type
    ) throws -> AIJSONSchema {
        guard let iterableType = type as? any CaseIterable.Type else {
            throw AIError.unsupportedFeature(
                "Enum \(type) must conform to CaseIterable for schema generation."
            )
        }

        let cases = extractStringCases(from: iterableType)
        guard !cases.isEmpty else {
            throw AIError.unsupportedFeature(
                "Enum \(type) has no string-representable cases. "
                    + "Only string-backed enums with CaseIterable are supported."
            )
        }

        return .string(enumValues: cases)
    }

    private static func extractStringCases(from type: any CaseIterable.Type) -> [String] {
        let allCases = type.allCases as any Collection
        return allCases.compactMap { value in
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .enum, mirror.children.isEmpty {
                if let rawRep = value as? any RawRepresentable {
                    return "\(rawRep.rawValue)"
                }
                return String(describing: value)
            }
            return nil
        }
    }

    private static func extractCodingKeys(for type: Any.Type) -> [String: String] {
        guard type is any Codable.Type else { return [:] }

        let extractor = CodingKeyExtractor()
        let instance = createDummyInstance(of: type)
        do {
            try (instance as? any Encodable)?.encode(to: extractor)
        } catch {
            return [:]
        }

        let mirror = Mirror(reflecting: instance)
        let propertyNames = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            return cleanPropertyName(label)
        }

        guard propertyNames.count == extractor.orderedKeys.count else {
            return [:]
        }

        var mapping: [String: String] = [:]
        for (propertyName, codingKeyName) in zip(propertyNames, extractor.orderedKeys) {
            if propertyName != codingKeyName {
                mapping[propertyName] = codingKeyName
            }
        }
        return mapping
    }

    private static func cleanPropertyName(_ name: String) -> String {
        if name.hasPrefix("_") {
            return String(name.dropFirst())
        }
        return name
    }

    private static func createDummyInstance(of type: Any.Type) -> Any {
        let size = MemoryLayout<Int>.size
        let alignment = MemoryLayout<Int>.alignment
        let realSize = _mangledTypeSize(type) ?? size
        let realAlignment = _mangledTypeAlignment(type) ?? alignment

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: max(realSize, 1),
            alignment: max(realAlignment, 1)
        )
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: max(realSize, 1))

        let instance = _unsafeBitCast(buffer, to: type)
        return instance
    }
}

private func _mangledTypeSize(_ type: Any.Type) -> Int? {
    MemoryLayout<Int>.size  // Fallback
}

private func _mangledTypeAlignment(_ type: Any.Type) -> Int? {
    MemoryLayout<Int>.alignment  // Fallback
}

private func _unsafeBitCast(_ pointer: UnsafeMutableRawPointer, to type: Any.Type) -> Any {
    func project<T>(_: T.Type) -> Any {
        pointer.assumingMemoryBound(to: T.self).pointee
    }
    return _openExistential(type, do: project)
}

/// Protocol witness for Optional to extract wrapped type.
protocol OptionalProtocol {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalProtocol {
    static var wrappedType: Any.Type { Wrapped.self }
}

/// Protocol witness for Array to extract element type.
protocol ArrayProtocol {
    static var elementType: Any.Type { get }
}

extension Array: ArrayProtocol {
    static var elementType: Any.Type { Element.self }
}

/// A minimal encoder that extracts CodingKeys mappings by observing which keys
/// a type's `encode(to:)` writes.
private final class CodingKeyExtractor: Encoder {
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]
    var orderedKeys: [String] = []

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = KeyExtractorKeyedContainer<Key>(extractor: self)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        DummyUnkeyedContainer(codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        DummySingleValueContainer(codingPath: codingPath)
    }
}

private struct KeyExtractorKeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let extractor: CodingKeyExtractor
    var codingPath: [any CodingKey] = []

    mutating func encodeNil(forKey key: Key) throws {
        recordKey(key)
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        recordKey(key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        recordKey(key)
        return KeyedEncodingContainer(
            KeyExtractorKeyedContainer<NestedKey>(extractor: extractor)
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        recordKey(key)
        return DummyUnkeyedContainer(codingPath: codingPath)
    }

    mutating func superEncoder() -> any Encoder {
        extractor
    }

    mutating func superEncoder(forKey key: Key) -> any Encoder {
        recordKey(key)
        return extractor
    }

    private func recordKey(_ key: Key) {
        if key.intValue == nil {
            extractor.orderedKeys.append(key.stringValue)
        }
    }
}

private struct DummyUnkeyedContainer: UnkeyedEncodingContainer {
    var codingPath: [any CodingKey]
    var count: Int = 0

    mutating func encodeNil() throws {}
    mutating func encode<T: Encodable>(_ value: T) throws {}
    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(DummyKeyedContainer<NestedKey>(codingPath: codingPath))
    }
    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        DummyUnkeyedContainer(codingPath: codingPath)
    }
    mutating func superEncoder() -> any Encoder {
        DummyEncoder(codingPath: codingPath)
    }
}

private struct DummyKeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    var codingPath: [any CodingKey]
    mutating func encodeNil(forKey key: Key) throws {}
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {}
    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(DummyKeyedContainer<NestedKey>(codingPath: codingPath))
    }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        DummyUnkeyedContainer(codingPath: codingPath)
    }
    mutating func superEncoder() -> any Encoder {
        DummyEncoder(codingPath: codingPath)
    }
    mutating func superEncoder(forKey key: Key) -> any Encoder {
        DummyEncoder(codingPath: codingPath)
    }
}

private struct DummySingleValueContainer: SingleValueEncodingContainer {
    var codingPath: [any CodingKey]
    mutating func encodeNil() throws {}
    mutating func encode<T: Encodable>(_ value: T) throws {}
}

private struct DummyEncoder: Encoder {
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(DummyKeyedContainer<Key>(codingPath: codingPath))
    }
    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        DummyUnkeyedContainer(codingPath: codingPath)
    }
    func singleValueContainer() -> any SingleValueEncodingContainer {
        DummySingleValueContainer(codingPath: codingPath)
    }
}

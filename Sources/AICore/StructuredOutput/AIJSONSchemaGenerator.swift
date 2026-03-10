import Foundation

/// Generates `AIJSONSchema` from `Codable` types using safe decode probing.
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
        if type is Decimal.Type {
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

        guard let decodableType = type as? any Decodable.Type else {
            throw unsupportedShapeError(for: type)
        }

        let inspection = try inspectProperties(of: decodableType)
        guard inspection.usedKeyedContainer else {
            throw unsupportedShapeError(for: type)
        }

        guard !inspection.properties.isEmpty else {
            throw AIError.unsupportedFeature(
                "Empty type \(type) cannot be reflected into a schema. Provide a manual jsonSchema override."
            )
        }

        var visitedWithSelf = visited
        visitedWithSelf.insert(typeID)

        var properties: [String: AIJSONSchema] = [:]
        var required: [String] = []

        for property in inspection.properties {
            properties[property.name] = try schemaForType(property.type, visited: visitedWithSelf)

            if !property.isOptional {
                required.append(property.name)
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
            guard let rawRepresentable = value as? any RawRepresentable,
                let rawValue = rawRepresentable.rawValue as? String
            else {
                return nil
            }

            return rawValue
        }
    }

    private static func inspectProperties(of type: any Decodable.Type) throws -> SchemaInspectionSnapshot {
        let inspection = SchemaInspection()

        do {
            _ = try type.init(from: SchemaProbeDecoder(inspection: inspection))
        } catch is SchemaProbeError {
            throw unsupportedShapeError(for: type)
        } catch {
            throw unsupportedShapeError(for: type)
        }

        return inspection.snapshot()
    }

    private static func unsupportedShapeError(for type: Any.Type) -> AIError {
        AIError.unsupportedFeature(
            "Unsupported type shape: \(type). "
                + "Only keyed structs/classes with supported Codable property types are supported."
        )
    }
}

private struct SchemaInspectionSnapshot {
    let usedKeyedContainer: Bool
    let properties: [SchemaProperty]
}

private struct SchemaProperty {
    let name: String
    let type: Any.Type
    let isOptional: Bool
}

private final class SchemaInspection {
    private(set) var usedKeyedContainer = false
    private var properties: [SchemaProperty] = []

    func markKeyedContainerUsed() {
        usedKeyedContainer = true
    }

    func recordProperty(name: String, type: Any.Type, isOptional: Bool) {
        if let existingIndex = properties.firstIndex(where: { $0.name == name }) {
            let existing = properties[existingIndex]
            properties[existingIndex] = SchemaProperty(
                name: existing.name,
                type: existing.type,
                isOptional: existing.isOptional && isOptional
            )
            return
        }

        properties.append(SchemaProperty(name: name, type: type, isOptional: isOptional))
    }

    func snapshot() -> SchemaInspectionSnapshot {
        SchemaInspectionSnapshot(usedKeyedContainer: usedKeyedContainer, properties: properties)
    }
}

private enum SchemaProbeError: Error {
    case unsupportedContainerShape
}

private final class SchemaProbeDecoder: Decoder {
    let inspection: SchemaInspection
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(
        inspection: SchemaInspection,
        codingPath: [any CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.inspection = inspection
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        inspection.markKeyedContainerUsed()
        let container = SchemaProbeKeyedContainer<Key>(inspection: inspection, codingPath: codingPath)
        return KeyedDecodingContainer(container)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw SchemaProbeError.unsupportedContainerShape
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw SchemaProbeError.unsupportedContainerShape
    }
}

private struct SchemaProbeKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let inspection: SchemaInspection
    let codingPath: [any CodingKey]

    var allKeys: [Key] { [] }

    func contains(_ key: Key) -> Bool {
        true
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        inspection.recordProperty(name: key.stringValue, type: Optional<String>.self, isOptional: true)
        return true
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        inspection.recordProperty(name: key.stringValue, type: type, isOptional: false)
        return try SchemaPlaceholderFactory.value(for: type)
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        inspection.recordProperty(name: key.stringValue, type: type, isOptional: true)
        return nil
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw SchemaProbeError.unsupportedContainerShape
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw SchemaProbeError.unsupportedContainerShape
    }

    func superDecoder() throws -> any Decoder {
        SchemaProbeDecoder(inspection: inspection, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        SchemaProbeDecoder(inspection: inspection, codingPath: codingPath + [key])
    }
}

private enum SchemaPlaceholderFactory {
    static func value<T: Decodable>(for type: T.Type) throws -> T {
        if type == String.self {
            return "" as! T
        }
        if type == Int.self {
            return 0 as! T
        }
        if type == Int8.self {
            return Int8(0) as! T
        }
        if type == Int16.self {
            return Int16(0) as! T
        }
        if type == Int32.self {
            return Int32(0) as! T
        }
        if type == Int64.self {
            return Int64(0) as! T
        }
        if type == UInt.self {
            return UInt(0) as! T
        }
        if type == UInt8.self {
            return UInt8(0) as! T
        }
        if type == UInt16.self {
            return UInt16(0) as! T
        }
        if type == UInt32.self {
            return UInt32(0) as! T
        }
        if type == UInt64.self {
            return UInt64(0) as! T
        }
        if type == Double.self {
            return Double.zero as! T
        }
        if type == Float.self {
            return Float.zero as! T
        }
        if type == Bool.self {
            return false as! T
        }
        if type == Date.self {
            return Date(timeIntervalSince1970: 0) as! T
        }
        if type == Decimal.self {
            return Decimal.zero as! T
        }

        if let optional = nilOptional(as: type) {
            return optional
        }

        if let array = emptyArray(as: type) {
            return array
        }

        if let enumCase = firstStringEnumCase(as: type) {
            return enumCase
        }

        return try T(from: SchemaProbeDecoder(inspection: SchemaInspection()))
    }

    private static func nilOptional<T: Decodable>(as type: T.Type) -> T? {
        guard let optionalType = type as? any OptionalProtocol.Type else {
            return nil
        }

        func makeNil<Wrapped>(_: Wrapped.Type) -> Any {
            Optional<Wrapped>.none as Any
        }

        let value = _openExistential(optionalType.wrappedType, do: makeNil)
        return value as? T
    }

    private static func emptyArray<T: Decodable>(as type: T.Type) -> T? {
        guard let arrayType = type as? any ArrayProtocol.Type else {
            return nil
        }

        func makeArray<Element>(_: Element.Type) -> Any {
            [Element]()
        }

        let value = _openExistential(arrayType.elementType, do: makeArray)
        return value as? T
    }

    private static func firstStringEnumCase<T: Decodable>(as type: T.Type) -> T? {
        guard let iterableType = type as? any CaseIterable.Type,
            type is any RawRepresentable.Type
        else {
            return nil
        }

        let allCases = iterableType.allCases as any Collection
        for value in allCases {
            guard let rawRepresentable = value as? any RawRepresentable,
                rawRepresentable.rawValue is String,
                let typedValue = value as? T
            else {
                continue
            }

            return typedValue
        }

        return nil
    }
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

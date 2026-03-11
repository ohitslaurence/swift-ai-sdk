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
        let probeContext = SchemaProbeContext(activeTypes: [ObjectIdentifier(type)])

        do {
            _ = try type.init(from: SchemaProbeDecoder(inspection: inspection, probeContext: probeContext))
        } catch SchemaProbeError.recursiveType(let recursiveType) {
            throw AIError.unsupportedFeature(
                "Recursive type detected: \(recursiveType). Provide a manual jsonSchema override."
            )
        } catch is SchemaProbeError {
            throw unsupportedShapeError(for: type)
        } catch {
            throw unsupportedShapeError(for: type)
        }

        if inspection.hasUncheckedConditionalKeys {
            throw AIError.unsupportedFeature(
                "Type \(type) uses conditional decoding that cannot be safely reflected. "
                    + "Provide a manual jsonSchema override."
            )
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
    private var conditionallyCheckedKeys: Set<String> = []
    private var nilCheckedKeys: Set<String> = []
    private var properties: [SchemaProperty] = []

    var hasUncheckedConditionalKeys: Bool {
        !conditionallyCheckedKeys.isEmpty
    }

    func markKeyedContainerUsed() {
        usedKeyedContainer = true
    }

    func recordProperty(name: String, type: Any.Type, isOptional: Bool) {
        conditionallyCheckedKeys.remove(name)
        let inferredIsOptional = isOptional || nilCheckedKeys.remove(name) != nil

        if let existingIndex = properties.firstIndex(where: { $0.name == name }) {
            let existing = properties[existingIndex]
            properties[existingIndex] = SchemaProperty(
                name: existing.name,
                type: existing.type,
                isOptional: existing.isOptional && inferredIsOptional
            )
            return
        }

        properties.append(SchemaProperty(name: name, type: type, isOptional: inferredIsOptional))
    }

    func markConditionalKeyCheck(_ name: String) {
        conditionallyCheckedKeys.insert(name)
    }

    func markNilCheck(_ name: String) {
        conditionallyCheckedKeys.insert(name)
        nilCheckedKeys.insert(name)
    }

    func snapshot() -> SchemaInspectionSnapshot {
        SchemaInspectionSnapshot(usedKeyedContainer: usedKeyedContainer, properties: properties)
    }
}

private enum SchemaProbeError: Error {
    case unsupportedContainerShape
    case recursiveType(Any.Type)
    case unsupportedPlaceholderType(Any.Type)
}

private struct SchemaProbeContext {
    let activeTypes: Set<ObjectIdentifier>

    init(activeTypes: Set<ObjectIdentifier>) {
        self.activeTypes = activeTypes
    }

    init(activeTypes: [ObjectIdentifier]) {
        self.activeTypes = Set(activeTypes)
    }

    func adding(_ type: Any.Type) -> Self {
        var next = activeTypes
        next.insert(ObjectIdentifier(type))
        return SchemaProbeContext(activeTypes: next)
    }
}

private final class SchemaProbeDecoder: Decoder {
    let inspection: SchemaInspection
    let probeContext: SchemaProbeContext
    let codingPath: [any CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(
        inspection: SchemaInspection,
        probeContext: SchemaProbeContext,
        codingPath: [any CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.inspection = inspection
        self.probeContext = probeContext
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        inspection.markKeyedContainerUsed()
        let container = SchemaProbeKeyedContainer<Key>(
            inspection: inspection,
            probeContext: probeContext,
            codingPath: codingPath
        )
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
    let probeContext: SchemaProbeContext
    let codingPath: [any CodingKey]

    var allKeys: [Key] { [] }

    func contains(_ key: Key) -> Bool {
        inspection.markConditionalKeyCheck(key.stringValue)
        return true
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        inspection.markNilCheck(key.stringValue)
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        inspection.recordProperty(name: key.stringValue, type: type, isOptional: false)
        return try SchemaPlaceholderFactory.value(for: type, probeContext: probeContext)
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
        SchemaProbeDecoder(inspection: inspection, probeContext: probeContext, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        SchemaProbeDecoder(
            inspection: inspection,
            probeContext: probeContext,
            codingPath: codingPath + [key]
        )
    }
}

private enum SchemaPlaceholderFactory {
    static func value<T: Decodable>(for type: T.Type, probeContext: SchemaProbeContext) throws -> T {
        if type == String.self {
            return try cast("", as: type)
        }
        if type == Int.self {
            return try cast(0, as: type)
        }
        if type == Int8.self {
            return try cast(Int8(0), as: type)
        }
        if type == Int16.self {
            return try cast(Int16(0), as: type)
        }
        if type == Int32.self {
            return try cast(Int32(0), as: type)
        }
        if type == Int64.self {
            return try cast(Int64(0), as: type)
        }
        if type == UInt.self {
            return try cast(UInt(0), as: type)
        }
        if type == UInt8.self {
            return try cast(UInt8(0), as: type)
        }
        if type == UInt16.self {
            return try cast(UInt16(0), as: type)
        }
        if type == UInt32.self {
            return try cast(UInt32(0), as: type)
        }
        if type == UInt64.self {
            return try cast(UInt64(0), as: type)
        }
        if type == Double.self {
            return try cast(Double.zero, as: type)
        }
        if type == Float.self {
            return try cast(Float.zero, as: type)
        }
        if type == Bool.self {
            return try cast(false, as: type)
        }
        if type == Date.self {
            return try cast(Date(timeIntervalSince1970: 0), as: type)
        }
        if type == Decimal.self {
            return try cast(Decimal.zero, as: type)
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

        if probeContext.activeTypes.contains(ObjectIdentifier(type)) {
            throw SchemaProbeError.recursiveType(type)
        }

        let nestedContext = probeContext.adding(type)
        return try T(
            from: SchemaProbeDecoder(
                inspection: SchemaInspection(),
                probeContext: nestedContext
            )
        )
    }

    private static func cast<T>(_ value: some Any, as type: T.Type) throws -> T {
        guard let typedValue = value as? T else {
            throw SchemaProbeError.unsupportedPlaceholderType(type)
        }

        return typedValue
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

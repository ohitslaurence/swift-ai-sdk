import AICore
import Foundation
import XCTest

final class ToolAndSchemaTests: XCTestCase {
    func test_tool_capturesSchemaHandlerAndApproval() async throws {
        let schema = AIJSONSchema.object(
            properties: ["city": .string()],
            required: ["city"]
        )
        let tool = AITool(
            name: "weather",
            description: "Lookup weather",
            inputSchema: schema,
            needsApproval: true
        ) { input in
            String(decoding: input, as: UTF8.self)
        }

        let result = try await tool.handler(Data("{\"city\":\"Paris\"}".utf8))

        XCTAssertEqual(tool.name, "weather")
        XCTAssertEqual(tool.description, "Lookup weather")
        XCTAssertEqual(tool.inputSchema, schema)
        XCTAssertTrue(tool.needsApproval)
        XCTAssertEqual(result, "{\"city\":\"Paris\"}")
    }

    func test_toolChoice_responseFormat_andSchema_roundTripThroughCodable() throws {
        let schema = AIJSONSchema.object(
            properties: [
                "status": .string(enumValues: ["ok", "error"]),
                "payload": .array(items: .ref("#")),
            ],
            required: ["status"],
            additionalProperties: true,
            description: "Root schema"
        )
        let choice = AIToolChoice.tool("weather")
        let format = AIResponseFormat.jsonSchema(schema, name: "status_payload")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(AIToolChoice.self, from: encoder.encode(choice)), choice)
        XCTAssertEqual(try decoder.decode(AIResponseFormat.self, from: encoder.encode(format)), format)
        XCTAssertEqual(try decoder.decode(AIJSONSchema.self, from: encoder.encode(schema)), schema)
        XCTAssertEqual(
            AIJSONSchema.anyJSON, try decoder.decode(AIJSONSchema.self, from: encoder.encode(AIJSONSchema.anyJSON)))
    }
}

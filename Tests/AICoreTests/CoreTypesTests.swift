import AICore
import Foundation
import XCTest

final class CoreTypesTests: XCTestCase {
    func test_request_initStoresAllFields() {
        let schema = AIJSONSchema.object(
            properties: ["city": .string(description: "City name")],
            required: ["city"]
        )
        let tool = AITool(
            name: "weather",
            description: "Lookup weather",
            inputSchema: schema,
            needsApproval: true
        ) { _ in "sunny" }
        let retryPolicy = RetryPolicy(maxRetries: 1, initialDelay: 0.25, backoffMultiplier: 3, maxDelay: 4)
        let timeout = AITimeout(total: 30, step: 10, chunk: 2)
        let request = AIRequest(
            model: AIModel("gpt-4o", provider: "openai"),
            messages: [.user("Hello")],
            systemPrompt: "Be concise",
            tools: [tool],
            toolChoice: .tool("weather"),
            allowParallelToolCalls: false,
            responseFormat: .jsonSchema(schema),
            maxTokens: 512,
            temperature: 0.2,
            topP: 0.9,
            stopSequences: ["END"],
            metadata: ["traceID": "123"],
            retryPolicy: retryPolicy,
            timeout: timeout,
            headers: ["X-Test": "1"]
        )

        XCTAssertEqual(request.model, AIModel("gpt-4o", provider: "openai"))
        XCTAssertEqual(request.messages, [.user("Hello")])
        XCTAssertEqual(request.systemPrompt, "Be concise")
        XCTAssertEqual(request.tools.count, 1)
        XCTAssertEqual(request.toolChoice, .tool("weather"))
        XCTAssertEqual(request.allowParallelToolCalls, false)
        XCTAssertEqual(request.responseFormat, .jsonSchema(schema))
        XCTAssertEqual(request.maxTokens, 512)
        XCTAssertEqual(request.temperature, 0.2)
        XCTAssertEqual(request.topP, 0.9)
        XCTAssertEqual(request.stopSequences, ["END"])
        XCTAssertEqual(request.metadata, ["traceID": "123"])
        XCTAssertEqual(request.retryPolicy, retryPolicy)
        XCTAssertEqual(request.timeout, timeout)
        XCTAssertEqual(request.headers, ["X-Test": "1"])
    }

    func test_messageHelpers_createExpectedMessages() {
        let user = AIMessage.user("Hello")
        let assistant = AIMessage.assistant([.text("Hi")])
        let tool = AIMessage.tool(id: "tool-1", content: "Sunny")

        XCTAssertEqual(user.role, .user)
        XCTAssertEqual(user.content, [.text("Hello")])
        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertEqual(assistant.content, [.text("Hi")])
        XCTAssertEqual(tool.role, .tool)

        guard case .toolResult(let result) = tool.content.first else {
            XCTFail("Expected tool result content")
            return
        }

        XCTAssertEqual(result, AIToolResult(toolUseId: "tool-1", content: "Sunny"))
        XCTAssertNil(AIRole(rawValue: "system"))
    }

    func test_mediaInputs_loadFromFileURLAndBase64() throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let documentData = Data("hello".utf8)
        let imageURL = try temporaryFileURL(named: "image.png", data: imageData)
        let documentURL = try temporaryFileURL(named: "doc.pdf", data: documentData)
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: documentURL)
        }

        let imageFromFile = try AIImage.from(fileURL: imageURL)
        let imageFromBase64 = try AIImage.from(base64: imageData.base64EncodedString(), mediaType: .png)
        let documentFromFile = try AIDocument.from(fileURL: documentURL)
        let documentFromBase64 = try AIDocument.from(
            base64: documentData.base64EncodedString(),
            mediaType: .plainText,
            filename: "doc.txt"
        )

        XCTAssertEqual(imageFromFile.data, imageData)
        XCTAssertEqual(imageFromFile.mediaType, .png)
        XCTAssertEqual(imageFromBase64.data, imageData)
        XCTAssertEqual(documentFromFile.data, documentData)
        XCTAssertEqual(documentFromFile.mediaType, .pdf)
        XCTAssertTrue(documentFromFile.filename?.hasSuffix("doc.pdf") == true)
        XCTAssertEqual(documentFromBase64.mediaType, .plainText)
        XCTAssertEqual(documentFromBase64.filename, "doc.txt")
    }

    private func temporaryFileURL(named name: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }
}

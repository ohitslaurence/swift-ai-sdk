import AICore
import AITestSupport
import Foundation
import XCTest

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class TransportAndSupportTests: XCTestCase {
    func test_providerCapabilitiesDefaultMatchesSpec() {
        let capabilities = AIProviderCapabilities.default

        XCTAssertEqual(capabilities.instructions.defaultFormat, .message(role: .system))
        XCTAssertNil(capabilities.instructions.reasoningModelFormatOverride)
        XCTAssertFalse(capabilities.structuredOutput.supportsJSONMode)
        XCTAssertFalse(capabilities.structuredOutput.supportsJSONSchema)
        XCTAssertEqual(capabilities.structuredOutput.defaultStrategy, .promptInjection)
        XCTAssertFalse(capabilities.inputs.supportsImages)
        XCTAssertFalse(capabilities.inputs.supportsDocuments)
        XCTAssertEqual(
            capabilities.tools, AIToolCapabilities(supportsParallelCalls: true, supportsForcedToolChoice: false))
        XCTAssertEqual(capabilities.streaming, AIStreamingCapabilities(includesUsageInStream: false))
        XCTAssertEqual(
            capabilities.embeddings,
            AIEmbeddingCapabilities(
                supportsEmbeddings: false,
                supportedInputKinds: [],
                supportsBatchInputs: false,
                supportsDimensionOverride: false
            )
        )
    }

    func test_mockTransport_returnsConfiguredDataAndStream() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let response = try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        let transport = MockTransport(
            dataHandler: { request in
                XCTAssertEqual(request.url, url)
                return (Data("ok".utf8), response)
            },
            streamHandler: { request in
                XCTAssertEqual(request.url, url)

                let body = AsyncThrowingStream<Data, any Error>(Data.self, bufferingPolicy: .unbounded) {
                    continuation in
                    continuation.yield(Data("a".utf8))
                    continuation.yield(Data("b".utf8))
                    continuation.finish()
                }

                return AIHTTPStreamResponse(response: response, body: body)
            }
        )
        let request = URLRequest(url: url)

        let (data, dataResponse) = try await transport.data(for: request)
        let streamResponse = try await transport.stream(for: request)
        var chunks: [String] = []
        for try await chunk in streamResponse.body {
            chunks.append(String(decoding: chunk, as: UTF8.self))
        }

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(dataResponse.statusCode, 200)
        XCTAssertEqual(streamResponse.response.statusCode, 200)
        XCTAssertEqual(chunks, ["a", "b"])
    }

    func test_providerHTTPConfigurationStoresBaseURLTransportAndHeaders() {
        let transport = MockTransport(
            dataHandler: { _ in
                throw AIError.unsupportedFeature("unused")
            },
            streamHandler: { _ in
                throw AIError.unsupportedFeature("unused")
            }
        )
        let baseURL = URL(string: "https://example.com")
        let configuration = AIProviderHTTPConfiguration(
            baseURL: baseURL,
            transport: transport,
            defaultHeaders: ["X-Test": "1"]
        )

        XCTAssertEqual(configuration.baseURL, baseURL)
        XCTAssertEqual(configuration.defaultHeaders, ["X-Test": "1"])
    }
}

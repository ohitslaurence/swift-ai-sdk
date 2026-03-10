import AICore
import Foundation
import XCTest

final class StreamTests: XCTestCase {
    func test_collect_buildsResponseWithTextToolUseUsageAndFinish() async throws {
        let stream = makeStream(
            events: [
                .start(id: "stream_1", model: "gpt-4o"),
                .delta(.text("Hel")),
                .delta(.text("lo")),
                .toolUseStart(id: "tool-1", name: "weather"),
                .delta(.toolInput(id: "tool-1", jsonDelta: "{\"city\":\"Lon")),
                .delta(.toolInput(id: "tool-1", jsonDelta: "don\"}")),
                .usage(AIUsage(inputTokens: 4, outputTokens: 2)),
                .finish(.toolUse),
            ]
        )

        let response = try await stream.collect()

        XCTAssertEqual(response.id, "stream_1")
        XCTAssertEqual(response.model, "gpt-4o")
        XCTAssertEqual(response.text, "Hello")
        XCTAssertEqual(response.finishReason, .toolUse)
        XCTAssertEqual(response.usage, AIUsage(inputTokens: 4, outputTokens: 2))
        XCTAssertEqual(response.content.count, 2)

        guard case .toolUse(let toolUse) = response.content[1] else {
            XCTFail("Expected collected tool use")
            return
        }

        XCTAssertEqual(toolUse.id, "tool-1")
        XCTAssertEqual(toolUse.name, "weather")
        XCTAssertEqual(String(decoding: toolUse.input, as: UTF8.self), "{\"city\":\"London\"}")
    }

    func test_collect_whenStreamEndsWithoutFinish_throwsStreamInterrupted() async {
        let stream = makeStream(
            events: [
                .start(id: "stream_2", model: "gpt-4o"),
                .delta(.text("partial")),
            ]
        )

        do {
            _ = try await stream.collect()
            XCTFail("Expected stream interruption")
        } catch let error as AIError {
            XCTAssertEqual(error, .streamInterrupted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_textStreamAndAccumulatedText_rethrowUpstreamErrors() async {
        let textError = AIError.serverError(statusCode: 500, message: "boom")

        do {
            var received: [String] = []
            for try await chunk in makeStream(events: [.delta(.text("hello"))], error: textError).textStream {
                received.append(chunk)
            }
            XCTFail("Expected text stream to fail")
        } catch let error as AIError {
            XCTAssertEqual(error, textError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            var received: [String] = []
            for try await chunk in makeStream(events: [.delta(.text("a")), .delta(.text("b"))], error: textError)
                .accumulatedText
            {
                received.append(chunk)
            }
            XCTFail("Expected accumulated text stream to fail")
        } catch let error as AIError {
            XCTAssertEqual(error, textError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_streamHelpers_shareSingleUnderlyingStream() async {
        let stream = makeStream(
            events: [
                .start(id: "stream_3", model: "gpt-4o"),
                .delta(.text("hello")),
                .finish(.stop),
            ]
        )

        do {
            var chunks: [String] = []
            for try await chunk in stream.textStream {
                chunks.append(chunk)
            }
            XCTAssertEqual(chunks, ["hello"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await stream.collect()
            XCTFail("Expected the consumed stream to have no remaining events")
        } catch let error as AIError {
            XCTAssertEqual(error, .noContentGenerated)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeStream(events: [AIStreamEvent], error: AIError? = nil) -> AIStream {
        AIStream(
            AsyncThrowingStream<AIStreamEvent, any Error>(AIStreamEvent.self, bufferingPolicy: .unbounded) {
                continuation in
                for event in events {
                    continuation.yield(event)
                }

                if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
        )
    }
}

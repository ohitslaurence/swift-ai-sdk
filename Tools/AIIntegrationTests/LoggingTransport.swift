import AICore
import Foundation

/// Wraps any AIHTTPTransport and logs full request/response details for debugging.
public struct LoggingTransport: AIHTTPTransport, Sendable {
    private let wrapped: any AIHTTPTransport

    public init(wrapping transport: any AIHTTPTransport) {
        self.wrapped = transport
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        logRequest(request)
        let start = ContinuousClock.now

        do {
            let (data, response) = try await wrapped.data(for: request)
            let elapsed = start.duration(to: .now)
            logDataResponse(data: data, response: response, elapsed: elapsed)
            return (data, response)
        } catch {
            logError(error)
            throw error
        }
    }

    public func stream(for request: URLRequest) async throws -> AIHTTPStreamResponse {
        logRequest(request)
        let start = ContinuousClock.now

        do {
            let streamResponse = try await wrapped.stream(for: request)
            let elapsed = start.duration(to: .now)
            logStreamResponseStart(response: streamResponse.response, elapsed: elapsed)

            let loggingBody = AsyncThrowingStream<Data, any Error> { continuation in
                let task = Task {
                    let streamStart = ContinuousClock.now
                    do {
                        for try await chunk in streamResponse.body {
                            let delta = streamStart.duration(to: .now)
                            logStreamChunk(chunk, elapsed: delta)
                            continuation.yield(chunk)
                        }
                        printSeparator("STREAM END")
                        continuation.finish()
                    } catch {
                        logError(error)
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in
                    task.cancel()
                }
            }

            return AIHTTPStreamResponse(response: streamResponse.response, body: loggingBody)
        } catch {
            logError(error)
            throw error
        }
    }
}

// MARK: - Logging Helpers

extension LoggingTransport {
    private func logRequest(_ request: URLRequest) {
        printSeparator("REQUEST")
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "<no url>"
        print("\(method) \(url)")

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            print("Headers:")
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                let displayValue = key.lowercased() == "authorization" ? redactAuthHeader(value) : value
                print("  \(key): \(displayValue)")
            }
        }

        if let body = request.httpBody {
            print("Body:")
            print(prettyPrintJSON(body))
        }
        print()
    }

    private func logDataResponse(data: Data, response: HTTPURLResponse, elapsed: Duration) {
        printSeparator("RESPONSE (\(response.statusCode))")
        let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        print("Latency: \(ms)ms")

        let headers = response.allHeaderFields
        if !headers.isEmpty {
            print("Headers:")
            let sorted = headers.sorted { "\($0.key)" < "\($1.key)" }
            for (key, value) in sorted {
                print("  \(key): \(value)")
            }
        }

        print("Body:")
        print(prettyPrintJSON(data))
        printSeparator("")
    }

    private func logStreamResponseStart(response: HTTPURLResponse, elapsed: Duration) {
        let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        printSeparator("STREAM RESPONSE (\(response.statusCode))")
        print("Connection Latency: \(ms)ms")

        let headers = response.allHeaderFields
        if !headers.isEmpty {
            print("Headers:")
            let sorted = headers.sorted { "\($0.key)" < "\($1.key)" }
            for (key, value) in sorted {
                print("  \(key): \(value)")
            }
        }
        print()
    }

    private func logStreamChunk(_ data: Data, elapsed: Duration) {
        let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        let text = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            if !line.isEmpty {
                print("  [\(ms)ms] \(line)")
            }
        }
    }

    private func logError(_ error: any Error) {
        printSeparator("ERROR")
        print("  \(error)")
        printSeparator("")
    }

    private func redactAuthHeader(_ value: String) -> String {
        let parts = value.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else {
            return value.count > 4 ? "...\(value.suffix(4))" : value
        }
        let scheme = parts[0]
        let token = parts[1]
        let lastFour = token.count > 4 ? String(token.suffix(4)) : String(token)
        return "\(scheme) ...\(lastFour)"
    }

    private func prettyPrintJSON(_ data: Data) -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: pretty, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
        }
        return string
    }

    private func printSeparator(_ label: String) {
        let total = 56
        if label.isEmpty {
            print(String(repeating: "\u{2550}", count: total))
        } else {
            let prefix = "\u{2550}\u{2550}\u{2550} \(label) "
            let remaining = max(0, total - prefix.count)
            print(prefix + String(repeating: "\u{2550}", count: remaining))
        }
    }
}

import AICore
import Foundation

struct OpenAIErrorMapper {
    func mapResponse(response: HTTPURLResponse, body: Data, model: AIModel) -> AIError {
        let message = errorMessage(from: body) ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)

        switch response.statusCode {
        case 400:
            return .invalidRequest(message)
        case 401:
            return .authenticationFailed
        case 404:
            return .modelNotFound(model.id)
        case 429:
            return .rateLimited(retryAfter: retryAfter(from: response))
        case 500...599:
            return .serverError(statusCode: response.statusCode, message: message)
        default:
            return .serverError(statusCode: response.statusCode, message: message)
        }
    }

    func mapTransportError(_ error: any Error) -> AIError {
        if let error = error as? AIError {
            return error
        }

        if error is CancellationError {
            return .cancelled
        }

        return .networkError(AIErrorContext(error))
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        if let milliseconds = response.value(forHTTPHeaderField: "retry-after-ms"),
            let retryAfterMilliseconds = Double(milliseconds), retryAfterMilliseconds >= 0
        {
            return retryAfterMilliseconds / 1_000
        }

        if let seconds = response.value(forHTTPHeaderField: "retry-after"),
            let retryAfterSeconds = Double(seconds), retryAfterSeconds >= 0
        {
            return retryAfterSeconds
        }

        return nil
    }

    private func errorMessage(from body: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: body),
            let message = envelope.error?.message, !message.isEmpty
        {
            return message
        }

        let bodyString = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bodyString?.isEmpty == false ? bodyString : nil
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    let error: OpenAIErrorPayload?
}

private struct OpenAIErrorPayload: Decodable {
    let message: String?
}

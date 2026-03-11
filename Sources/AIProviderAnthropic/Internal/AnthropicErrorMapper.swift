import AICore
import Foundation

struct AnthropicErrorMapper {
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
        case 409, 500...599:
            return .serverError(statusCode: response.statusCode, message: message)
        default:
            return .serverError(statusCode: response.statusCode, message: message)
        }
    }

    func mapStreamError(body: Data, model: AIModel) -> AIError {
        guard let payload = errorPayload(from: body) else {
            return .decodingError(
                AIErrorContext(message: "Anthropic stream error events must contain a valid error payload")
            )
        }

        guard let type = payload.type?.trimmingCharacters(in: .whitespacesAndNewlines), !type.isEmpty,
            let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty
        else {
            return .decodingError(
                AIErrorContext(message: "Anthropic stream error events must include a non-empty error type and message")
            )
        }

        switch type {
        case "invalid_request_error":
            return .invalidRequest(message)
        case "authentication_error":
            return .authenticationFailed
        case "permission_error":
            return .serverError(statusCode: 403, message: message)
        case "not_found_error":
            return .modelNotFound(model.id)
        case "request_too_large":
            return .serverError(statusCode: 413, message: message)
        case "rate_limit_error":
            return .rateLimited(retryAfter: nil)
        case "overloaded_error":
            return .serverError(statusCode: 529, message: message)
        case "api_error":
            return .serverError(statusCode: 500, message: message)
        default:
            return .serverError(statusCode: 500, message: "\(type): \(message)")
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
            let retryAfterMilliseconds = Double(milliseconds.trimmingCharacters(in: .whitespacesAndNewlines)),
            retryAfterMilliseconds >= 0
        {
            return retryAfterMilliseconds / 1_000
        }

        if let seconds = response.value(forHTTPHeaderField: "retry-after"),
            let retryAfter = retryAfter(from: seconds)
        {
            return retryAfter
        }

        return nil
    }

    private func retryAfter(from value: String) -> TimeInterval? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let seconds = Double(trimmedValue), seconds >= 0 {
            return seconds
        }

        guard let date = httpDate(from: trimmedValue) else {
            return nil
        }

        return max(0, date.timeIntervalSinceNow)
    }

    private func httpDate(from value: String) -> Date? {
        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ]

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func errorMessage(from body: Data) -> String? {
        if let message = errorPayload(from: body)?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
            !message.isEmpty
        {
            return message
        }

        let bodyString = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return bodyString?.isEmpty == false ? bodyString : nil
    }

    private func errorPayload(from body: Data) -> AnthropicErrorPayload? {
        (try? JSONDecoder().decode(AnthropicErrorEnvelope.self, from: body))?.error
    }
}

private struct AnthropicErrorEnvelope: Decodable {
    let error: AnthropicErrorPayload?
}

private struct AnthropicErrorPayload: Decodable {
    let type: String?
    let message: String?
}

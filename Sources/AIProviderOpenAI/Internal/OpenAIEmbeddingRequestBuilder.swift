import AICore
import Foundation

struct OpenAIEmbeddingRequestBuilder {
    private static let defaultBaseURL: URL = {
        guard let url = URL(string: "https://api.openai.com") else {
            preconditionFailure("OpenAI base URL must be valid")
        }

        return url
    }()

    private let apiKey: String
    private let organization: String?
    private let configuration: AIProviderHTTPConfiguration

    init(apiKey: String, organization: String?, configuration: AIProviderHTTPConfiguration) {
        self.apiKey = apiKey
        self.organization = organization
        self.configuration = configuration
    }

    func prepareRequest(for request: AIEmbeddingRequest) throws -> OpenAIPreparedEmbeddingRequest {
        guard !request.inputs.isEmpty else {
            throw AIError.invalidRequest("Embedding inputs must not be empty")
        }

        if let dimensions = request.dimensions, dimensions <= 0 {
            throw AIError.invalidRequest("Embedding dimensions must be greater than 0")
        }

        var warnings: [AIProviderWarning] = []
        let inputStrings = request.inputs.map { input -> String in
            switch input {
            case .text(let text):
                return text
            }
        }

        let payload = OpenAIEmbeddingPayload(
            model: request.model.id,
            input: inputStrings.count == 1 ? .string(inputStrings[0]) : .array(inputStrings),
            dimensions: normalizedDimensions(request.dimensions, for: request.model, warnings: &warnings)
        )

        var urlRequest = URLRequest(url: endpointURL())
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        var headers = configuration.defaultHeaders
        headers.merge(request.headers) { _, new in new }
        headers["Authorization"] = "Bearer \(apiKey)"
        headers["Content-Type"] = "application/json"

        if let organization {
            headers["OpenAI-Organization"] = organization
        }

        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        return OpenAIPreparedEmbeddingRequest(urlRequest: urlRequest, warnings: warnings)
    }

    private func endpointURL() -> URL {
        (configuration.baseURL ?? Self.defaultBaseURL).appending(path: "v1/embeddings")
    }

    private func normalizedDimensions(
        _ dimensions: Int?,
        for model: AIModel,
        warnings: inout [AIProviderWarning]
    ) -> Int? {
        guard let dimensions else {
            return nil
        }

        guard supportsDimensionOverride(for: model) else {
            warnings.append(
                AIProviderWarning(
                    code: "unsupported_embedding_dimensions",
                    message:
                        "The `dimensions` parameter is only supported for known OpenAI dimension-configurable embedding models; the setting has been dropped for \(model.id).",
                    parameter: "dimensions"
                )
            )
            return nil
        }

        return dimensions
    }

    private func supportsDimensionOverride(for model: AIModel) -> Bool {
        switch model.id {
        case "text-embedding-3-small", "text-embedding-3-large":
            return true
        default:
            return false
        }
    }
}

struct OpenAIPreparedEmbeddingRequest {
    let urlRequest: URLRequest
    let warnings: [AIProviderWarning]
}

private struct OpenAIEmbeddingPayload: Encodable {
    let model: String
    let input: OpenAIEmbeddingInputPayload
    let dimensions: Int?
}

private enum OpenAIEmbeddingInputPayload: Encodable {
    case string(String)
    case array([String])

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        }
    }
}

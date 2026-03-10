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

    func prepareRequest(for request: AIEmbeddingRequest) throws -> URLRequest {
        let inputStrings = request.inputs.map { input -> String in
            switch input {
            case .text(let text):
                return text
            }
        }

        let payload = OpenAIEmbeddingPayload(
            model: request.model.id,
            input: inputStrings,
            dimensions: request.dimensions
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

        return urlRequest
    }

    private func endpointURL() -> URL {
        (configuration.baseURL ?? Self.defaultBaseURL).appending(path: "v1/embeddings")
    }
}

private struct OpenAIEmbeddingPayload: Encodable {
    let model: String
    let input: [String]
    let dimensions: Int?
}

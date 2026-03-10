import AICore
import Foundation

struct OpenAIEmbeddingResponseParser {
    func parse(_ data: Data) throws -> AIEmbeddingResponse {
        do {
            let response = try JSONDecoder().decode(OpenAIEmbeddingAPIResponse.self, from: data)

            let embeddings = response.data.map { item in
                AIEmbedding(index: item.index, vector: item.embedding)
            }

            let usage: AIUsage?
            if let apiUsage = response.usage {
                usage = AIUsage(inputTokens: apiUsage.totalTokens, outputTokens: 0)
            } else {
                usage = nil
            }

            return AIEmbeddingResponse(
                model: response.model,
                embeddings: embeddings,
                usage: usage
            )
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.decodingError(AIErrorContext(error))
        }
    }
}

private struct OpenAIEmbeddingAPIResponse: Decodable {
    let model: String
    let data: [OpenAIEmbeddingData]
    let usage: OpenAIEmbeddingUsage?
}

private struct OpenAIEmbeddingData: Decodable {
    let index: Int
    let embedding: [Float]
}

private struct OpenAIEmbeddingUsage: Decodable {
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
    }
}

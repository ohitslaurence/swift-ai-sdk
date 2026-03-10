import AI

let request = AIEmbeddingRequest(
    model: .openAIEmbedding(.textEmbedding3Small),
    inputs: [.text("swift")]
)

print("Embeddings scaffold for model: \(request.model.id)")

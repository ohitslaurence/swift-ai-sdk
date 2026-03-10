import AI

let provider = OpenAIProvider(apiKey: "demo")
let request = AIRequest(model: .gpt(.gpt4oMini), messages: [.user("Hello")])

print("Model: \(request.model.id)")
print("Available models: \(provider.availableModels.map(\.id).joined(separator: ", "))")

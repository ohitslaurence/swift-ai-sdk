import AI

let request = AIRequest(model: .gpt(.gpt4oMini), messages: [.user("List three colors")])
print("Structured output scaffold request for model: \(request.model.id)")

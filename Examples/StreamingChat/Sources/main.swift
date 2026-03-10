import AI

let stream = AIStream.finished(text: "Streaming scaffold")

for try await chunk in stream.textStream {
    print(chunk)
}

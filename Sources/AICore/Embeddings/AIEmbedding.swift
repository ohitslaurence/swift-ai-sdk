/// A single embedding vector.
public struct AIEmbedding: Sendable, Codable, Equatable {
    public let index: Int
    public let vector: [Float]

    public init(index: Int, vector: [Float]) {
        self.index = index
        self.vector = vector
    }

    public var dimensions: Int {
        vector.count
    }
}

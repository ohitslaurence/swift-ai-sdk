import Foundation

/// A tool call emitted by the model.
public struct AIToolUse: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let input: Data

    public init(id: String, name: String, input: Data) {
        self.id = id
        self.name = name
        self.input = input
    }
}

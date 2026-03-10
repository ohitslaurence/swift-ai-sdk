#if canImport(SwiftUI)
    import AICore
    import SwiftUI

    /// A minimal message bubble view.
    public struct MessageBubble: View {
        public let message: AIMessage

        public init(message: AIMessage) {
            self.message = message
        }

        public var body: some View {
            Text(
                message.content.compactMap {
                    if case .text(let value) = $0 {
                        return value
                    }
                    return nil
                }.joined(separator: "\n")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif

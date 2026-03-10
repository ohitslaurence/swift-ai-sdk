#if canImport(SwiftUI)
    import AICore
    import SwiftUI

    /// A basic message list view.
    public struct AIMessageList: View {
        public let messages: [AIMessage]
        public var streamingText: String?

        public init(_ messages: [AIMessage], streamingText: String? = nil) {
            self.messages = messages
            self.streamingText = streamingText
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        MessageBubble(message: message)
                    }

                    if let streamingText, !streamingText.isEmpty {
                        Text(streamingText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
#endif

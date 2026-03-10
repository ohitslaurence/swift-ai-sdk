#if canImport(SwiftUI)
    import AICore
    import SwiftUI

    /// A basic message list view with auto-scroll support.
    public struct AIMessageList: View {
        public let messages: [AIMessage]
        public var streamingText: String?

        @State private var isNearBottom = true

        public init(_ messages: [AIMessage], streamingText: String? = nil) {
            self.messages = messages
            self.streamingText = streamingText
        }

        public var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                            MessageBubble(message: message)
                        }

                        if let streamingText, !streamingText.isEmpty {
                            Text(streamingText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .onChange(of: messages.count) {
                    scrollToBottomIfNeeded(proxy: proxy)
                }
                .onChange(of: streamingText) {
                    scrollToBottomIfNeeded(proxy: proxy)
                }
            }
        }

        private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
            guard isNearBottom else { return }
            withAnimation {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
#endif

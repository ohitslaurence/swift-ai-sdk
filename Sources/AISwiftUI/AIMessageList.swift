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
                    .background(
                        GeometryReader { contentGeometry in
                            Color.clear.preference(
                                key: ContentHeightKey.self,
                                value: contentGeometry.size.height
                            )
                        }
                    )
                }
                .onPreferenceChange(ContentHeightKey.self) { _ in
                    // Preference fires on layout changes; used to detect
                    // when content grows. The actual near-bottom check
                    // relies on the scroll view's coordinate space below.
                }
                .background(
                    GeometryReader { scrollGeometry in
                        Color.clear
                            .onChange(of: scrollGeometry.frame(in: .global)) {
                                updateNearBottom(scrollFrame: scrollGeometry)
                            }
                    }
                )
                .onChange(of: messages.count) {
                    scrollToBottomIfNeeded(proxy: proxy)
                }
                .onChange(of: streamingText) {
                    scrollToBottomIfNeeded(proxy: proxy)
                }
            }
        }

        private func updateNearBottom(scrollFrame: GeometryProxy) {
            let frame = scrollFrame.frame(in: .global)
            let contentHeight = scrollFrame.size.height
            let threshold: CGFloat = 80
            isNearBottom = contentHeight <= frame.height + threshold
        }

        private func scrollToBottomIfNeeded(proxy: ScrollViewProxy) {
            guard isNearBottom else { return }
            withAnimation {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private struct ContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
#endif

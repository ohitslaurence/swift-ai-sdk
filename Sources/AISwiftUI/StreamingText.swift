#if canImport(SwiftUI)
    import SwiftUI

    /// A simple streaming text view with an optional blinking cursor.
    public struct StreamingText: View {
        public let state: AIStreamState
        public var showCursor: Bool
        public var font: Font

        @State private var cursorVisible = true

        public init(_ state: AIStreamState, showCursor: Bool = true, font: Font = .body) {
            self.state = state
            self.showCursor = showCursor
            self.font = font
        }

        public var body: some View {
            Text(state.text + cursorSuffix)
                .font(font)
                .onChange(of: state.isStreaming) { _, isStreaming in
                    cursorVisible = isStreaming
                }
                .task(id: state.isStreaming) {
                    guard state.isStreaming, showCursor else { return }
                    cursorVisible = true
                    while !Task.isCancelled, state.isStreaming {
                        try? await Task.sleep(nanoseconds: 530_000_000)
                        guard !Task.isCancelled, state.isStreaming else { break }
                        cursorVisible.toggle()
                    }
                    cursorVisible = false
                }
        }

        private var cursorSuffix: String {
            (showCursor && state.isStreaming && cursorVisible) ? "|" : ""
        }
    }
#endif

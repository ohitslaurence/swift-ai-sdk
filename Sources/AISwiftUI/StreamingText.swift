#if canImport(SwiftUI)
    import SwiftUI

    /// A simple streaming text view.
    public struct StreamingText: View {
        public let state: AIStreamState
        public var showCursor: Bool
        public var font: Font

        public init(_ state: AIStreamState, showCursor: Bool = true, font: Font = .body) {
            self.state = state
            self.showCursor = showCursor
            self.font = font
        }

        public var body: some View {
            Text(state.text + ((showCursor && state.isStreaming) ? "|" : ""))
                .font(font)
        }
    }
#endif

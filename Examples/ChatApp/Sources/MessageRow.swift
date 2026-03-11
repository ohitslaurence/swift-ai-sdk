import AICore
import SwiftUI

struct MessageRow: View {
    let text: String
    let role: AIRole
    var isStreaming: Bool = false

    init(message: AIMessage) {
        self.text = message.content.compactMap {
            if case .text(let value) = $0 { return value }
            return nil
        }.joined(separator: "\n")
        self.role = message.role
        self.isStreaming = false
    }

    init(text: String, role: AIRole, isStreaming: Bool = false) {
        self.text = text
        self.role = role
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 60) }

            VStack(alignment: role == .user ? .trailing : .leading, spacing: 4) {
                Text(role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Text(text)
                        .textSelection(.enabled)
                    if isStreaming {
                        Text("|")
                            .foregroundStyle(.secondary)
                            .blinkingCursor()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        role == .user
            ? AnyShapeStyle(Color.accentColor.opacity(0.15))
            : AnyShapeStyle(Color(.controlBackgroundColor))
    }
}

private struct BlinkingCursor: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}

extension View {
    fileprivate func blinkingCursor() -> some View {
        modifier(BlinkingCursor())
    }
}

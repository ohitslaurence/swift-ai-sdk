import AICore
import AIProviderAnthropic
import AIProviderOpenAI
import AISwiftUI
import SwiftUI

struct ContentView: View {
    @State private var settings = ChatSettings()
    @State private var conversation: AIConversation?
    @State private var inputText = ""
    @State private var showSettings = true
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            settingsBar
            Divider()
            messageArea
            Divider()
            inputBar
        }
        .onChange(of: settings.provider) { _, newProvider in
            settings.selectedModelID = newProvider.defaultModelID
            resetConversation()
        }
        .onChange(of: settings.selectedModelID) { _, _ in resetConversation() }
        .onChange(of: settings.apiKey) { _, _ in resetConversation() }
    }

    @ViewBuilder
    private var settingsBar: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Picker("Provider", selection: $settings.provider) {
                        ForEach(ProviderOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Picker("Model", selection: $settings.selectedModelID) {
                        ForEach(settings.availableModelIDs, id: \.self) { id in
                            Text(id).tag(id)
                        }
                    }
                    .frame(maxWidth: 250)
                }

                HStack {
                    SecureField("API Key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)

                    if !settings.apiKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "gearshape")
                Text("Configuration")
                    .font(.headline)
                Spacer()
                if let conversation {
                    tokenBadge(conversation.totalUsage)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func tokenBadge(_ usage: AIUsage) -> some View {
        if usage.inputTokens > 0 || usage.outputTokens > 0 {
            Text("\(usage.inputTokens + usage.outputTokens) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
    }

    @ViewBuilder
    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let conversation {
                        ForEach(Array(conversation.messages.enumerated()), id: \.offset) { _, message in
                            MessageRow(message: message)
                        }

                        if !conversation.currentStreamText.isEmpty {
                            MessageRow(
                                text: conversation.currentStreamText,
                                role: .assistant,
                                isStreaming: true
                            )
                        }

                        if let error = conversation.error {
                            errorBanner(error)
                        }
                    } else {
                        emptyState
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(16)
            }
            .onChange(of: conversation?.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversation?.currentStreamText) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.textBackgroundColor))
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Enter an API key and start chatting")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    @ViewBuilder
    private func errorBanner(_ error: AIError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .font(.callout)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : Color.gray)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)

            if conversation?.isStreaming == true {
                Button(action: { conversation?.cancel() }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !settings.apiKey.isEmpty
            && conversation?.isStreaming != true
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !settings.apiKey.isEmpty else { return }

        if conversation == nil {
            conversation = settings.makeConversation()
        }

        conversation?.send(text)
        inputText = ""
        showSettings = false
    }

    private func resetConversation() {
        conversation?.cancel()
        conversation = nil
    }
}

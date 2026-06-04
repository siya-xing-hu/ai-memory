import SwiftUI

struct ChatView: View {
    let messages: [ChatMessage]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(messages, id: \.id) { message in
                        ChatMessageRow(message: message)
                            .id(message.id)
                    }

                    if isLoading {
                        HStack {
                            Spacer(minLength: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("思考中...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(16)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .id("loading-indicator")
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isLoading) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let lastId = messages.last?.id {
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            } else if isLoading {
                withAnimation {
                    proxy.scrollTo("loading-indicator", anchor: .bottom)
                }
            }
        }
    }
}

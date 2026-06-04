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

                }
                .padding(.vertical, 8)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let lastId = messages.last?.id {
                withAnimation {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }
}

import SwiftUI

struct DayChatDetailView: View {
    let store: DayChatStore
    let date: Date

    var body: some View {
        Group {
            if let chat = store.dayChat(for: date) {
                let messages = chat.messages.sorted(by: { $0.createdAt < $1.createdAt })
                if messages.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(messages) { message in
                                ChatMessageRow(message: message)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            } else {
                emptyState
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("当天暂无对话记录")
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            return "今天的对话"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天的对话"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
            return formatter.string(from: date)
        }
    }
}

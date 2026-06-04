import SwiftUI

struct DaySummaryView: View {
    let store: DayChatStore
    let date: Date
    @State private var reviewText = ""
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading {
                    ProgressView("生成中...")
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                if !reviewText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI 回顾")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(reviewText)
                            .font(.body)
                            .lineSpacing(6)
                    }
                    .padding(.horizontal)
                    Divider()
                }

                let topics = store.topicSummariesForDate(date)
                if topics.isEmpty {
                    Text("当天暂无汇总记录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(topics) { topic in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(topic.title)
                                .font(.headline)
                            Text(topic.summary)
                                .font(.body)
                            Divider()
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: DayChatDetailView(store: store, date: date)) {
                    Text("详细对话")
                }
            }
        }
        .onAppear {
            generateReview()
        }
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(date) {
            return "今天"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
            return formatter.string(from: date)
        }
    }

    private func generateReview() {
        let topics = store.topicSummariesForDate(date)
        guard !topics.isEmpty else { return }
        guard reviewText.isEmpty else { return }
        isLoading = true
        Task {
            guard await AIService.shared.isConfigured() else {
                isLoading = false
                return
            }
            do {
                let contents = topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
                let prompt = """
                请根据当天话题汇总生成一份回顾总结。

                当天话题：
                \(contents)

                请用中文输出，按话题分组，简洁明了。
                """
                let review = try await AIService.shared.generateResponse(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    context: nil
                )
                await MainActor.run {
                    reviewText = review
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    reviewText = "生成失败"
                    isLoading = false
                }
            }
        }
    }
}

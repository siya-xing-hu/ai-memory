import SwiftUI

struct DailyReviewView: View {
    let store: DayChatStore
    @State private var reviewText = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        ProgressView("生成中...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if !reviewText.isEmpty {
                        Text(reviewText)
                            .font(.body)
                            .lineSpacing(6)
                    } else {
                        let topics = store.topicSummariesForDate(Date())
                        if topics.isEmpty {
                            Text("今日暂无汇总记录")
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
                }
                .padding()
            }
            .navigationTitle("今日回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                generateReview()
            }
        }
    }

    private func generateReview() {
        let topics = store.topicSummariesForDate(Date())
        guard !topics.isEmpty else { return }
        isLoading = true
        Task {
            guard await AIService.shared.isConfigured() else {
                isLoading = false
                return
            }
            do {
                let contents = topics.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n")
                let prompt = """
                请根据今日话题汇总生成一份回顾总结。

                今日话题：
                \(contents)

                请用中文输出，按话题分组，简洁明了。
                """
                let review = try await AIService.shared.generateResponse(
                    messages: [ChatMessage(role: .user, content: prompt)],
                    context: nil
                )
                reviewText = review
                isLoading = false
            } catch {
                reviewText = "生成失败"
                isLoading = false
            }
        }
    }
}

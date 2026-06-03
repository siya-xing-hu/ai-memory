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
                        Text("今日暂无记录")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
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
        // Temporary stub - will be properly implemented in Task 11
        let messages = store.messagesForToday()
        guard !messages.isEmpty else { return }
        reviewText = "今日共 \(messages.count) 条消息"
    }
}

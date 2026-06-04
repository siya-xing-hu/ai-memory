import SwiftUI

struct TopicRow: View {
    let topic: TopicSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            Text(topic.title)
                .font(.headline)
            Text(topic.summary)
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        if Calendar.current.isDateInToday(topic.dayChatDate) {
            formatter.dateFormat = "今天 · MM月dd日"
        } else if Calendar.current.isDateInYesterday(topic.dayChatDate) {
            formatter.dateFormat = "昨天 · MM月dd日"
        } else {
            formatter.dateFormat = "yyyy年MM月dd日"
        }
        return formatter.string(from: topic.dayChatDate)
    }
}

extension TopicSummary: Identifiable {}

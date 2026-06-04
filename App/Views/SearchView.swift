import SwiftUI

struct SearchView: View {
    let store: DayChatStore
    @State private var query = ""
    @State private var searchType: SearchType = .keyword
    @Environment(\.dismiss) private var dismiss

    enum SearchType {
        case keyword, semantic
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Picker("搜索方式", selection: $searchType) {
                    Text("关键词").tag(SearchType.keyword)
                    Text("语义").tag(SearchType.semantic)
                }
                .pickerStyle(.segmented)
                .padding()

                List(store.searchResults) { topic in
                    TopicRow(topic: topic)
                }
                .listStyle(.plain)
            }
            .navigationTitle("搜索记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索你的记忆...", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
        .onChange(of: query) { _, newValue in
            Task { @MainActor in
                await store.search(query: newValue)
            }
        }
    }
}

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

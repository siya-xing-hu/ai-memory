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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title)
                            .font(.headline)
                        Text(topic.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
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

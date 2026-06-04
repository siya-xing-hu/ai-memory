import SwiftUI

struct CalendarView: View {
    let store: DayChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var datesWithChats: Set<Date> = []

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if query.isEmpty {
                    calendarContent
                } else {
                    searchResults
                }
            }
            .navigationTitle("回顾")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                datesWithChats = store.datesWithChats()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索你的记忆...", text: $query)
                .textFieldStyle(.plain)
                .submitLabel(.search)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: query) { _, newValue in
            Task { @MainActor in
                await store.search(query: newValue)
            }
        }
    }

    // MARK: - Calendar Content

    private var calendarContent: some View {
        VStack(spacing: 16) {
            monthHeader
            weekdayHeader
            monthGrid
            Spacer()
        }
        .padding()
    }

    private var monthHeader: some View {
        HStack {
            Button(action: { changeMonth(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            Spacer()
            Text(monthTitle)
                .font(.headline)
            Spacer()
            Button(action: { changeMonth(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let days = daysInMonthGrid()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
            ForEach(0..<days.count, id: \.self) { index in
                if let date = days[index] {
                    dayCell(for: date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let hasChat = datesWithChats.contains(calendar.startOfDay(for: date))
        let isToday = calendar.isDateInToday(date)
        let dayNumber = calendar.component(.day, from: date)

        return Group {
            if hasChat {
                NavigationLink(destination: DaySummaryView(store: store, date: date)) {
                    cellContent(dayNumber: dayNumber, isToday: isToday, hasChat: true)
                }
                .buttonStyle(.plain)
            } else {
                cellContent(dayNumber: dayNumber, isToday: isToday, hasChat: false)
            }
        }
    }

    private func cellContent(dayNumber: Int, isToday: Bool, hasChat: Bool) -> some View {
        VStack(spacing: 4) {
            Text("\(dayNumber)")
                .font(.body)
                .foregroundColor(hasChat ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isToday ? Color.blue.opacity(0.2) : Color.clear)
                )
            Circle()
                .fill(hasChat ? Color.blue : Color.clear)
                .frame(width: 6, height: 6)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    // MARK: - Search Results

    private var searchResults: some View {
        Group {
            if store.searchResults.isEmpty {
                VStack {
                    Spacer()
                    Text("暂无匹配结果")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(store.searchResults) { topic in
                    NavigationLink(destination: DaySummaryView(store: store, date: topic.dayChatDate)) {
                        TopicRow(topic: topic)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        ["日", "一", "二", "三", "四", "五", "六"]
    }

    private func changeMonth(by offset: Int) {
        if let newDate = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = newDate
        }
    }

    private func daysInMonthGrid() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = firstWeekday - 1

        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }
        let daysInMonth = range.count

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                cells.append(date)
            }
        }
        return cells
    }
}

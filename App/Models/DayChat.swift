import Foundation
import SwiftData

@Model
class DayChat: @unchecked Sendable {
    @Attribute(.unique) var date: Date
    var messages: [ChatMessage]
    var summarizedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        date: Date,
        messages: [ChatMessage] = [],
        summarizedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.date = Calendar.current.startOfDay(for: date)
        self.messages = messages
        self.summarizedAt = summarizedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

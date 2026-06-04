import Foundation
import SwiftData

@Model
class TopicSummary: @unchecked Sendable {
    var id: UUID
    var dayChatDate: Date
    var title: String
    var summary: String
    var citedMessageIds: [UUID]
    var aiContextIds: [UUID]
    var embedding: [Double]?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        dayChatDate: Date,
        title: String,
        summary: String,
        citedMessageIds: [UUID],
        aiContextIds: [UUID] = [],
        embedding: [Double]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dayChatDate = dayChatDate
        self.title = title
        self.summary = summary
        self.citedMessageIds = citedMessageIds
        self.aiContextIds = aiContextIds
        self.embedding = embedding
        self.createdAt = createdAt
    }
}

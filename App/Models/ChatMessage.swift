import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user
    case ai
}

@Model
class ChatMessage: @unchecked Sendable {
    var id: UUID
    var role: MessageRole
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

import Foundation

struct ConversationItem: Identifiable, Equatable {
    enum Role { case assistant, user, error }
    let id = UUID()
    let role: Role
    let text: String
}

struct MailMessage: Codable, Identifiable {
    let id: String
    let sender: String
    let subject: String
    let receivedAt: String
    let mailbox: String
    let snippet: String
    let unsubscribeUrls: [String]
    let localID: String?
    let replyTo: String?
    var summary: String?
    var deadline: String?
    var suggestion: String?
    var priority: String?
    var needsReply: Bool?
    var dueToday: Bool?
    var risky: Bool?
    var cardID: String { "\(id):\(localID ?? "")" }
}

struct MailSnapshot: Codable {
    let messages: [MailMessage]
    var count: Int { messages.count }
    enum CodingKeys: String, CodingKey { case messages, count }
    init(messages: [MailMessage]) { self.messages = messages }
    init(from decoder: Decoder) throws {
        messages = try decoder.container(keyedBy: CodingKeys.self).decode([MailMessage].self, forKey: .messages)
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encode(count, forKey: .count)
    }
}

struct StructuredAnalysis: Decodable {
    struct Card: Decodable {
        let id: String
        let summary: String
        let deadline: String
        let suggestion: String
        let priority: String
        let needsReply: Bool
        let dueToday: Bool
        let risky: Bool
    }
    let cards: [Card]

    func applying(to sources: [MailMessage]) throws -> [MailMessage] {
        // Reject partial or mismatched output rather than silently showing wrong annotations.
        guard cards.count == sources.count,
              Set(cards.map(\.id)) == Set(sources.map(\.id)),
              Set(cards.map(\.id)).count == cards.count else {
            throw AssistantError("分析结果与邮件来源不匹配，请重试整理。")
        }
        return sources.map { source in
            var message = source
            let card = cards.first { $0.id == source.id }!
            message.summary = card.summary
            message.deadline = card.deadline
            message.suggestion = card.suggestion
            message.priority = card.priority
            message.needsReply = card.needsReply
            message.dueToday = card.dueToday
            message.risky = card.risky
            return message
        }
    }
}

struct FollowUpResult: Decodable {
    let kind: String
    let text: String
}

struct MailTaskResult {
    let text: String
    let kind: String
    let messages: [MailMessage]
}

enum MailFilter: String, CaseIterable {
    case all = "全部邮件", today = "今日待办", replies = "需要回复", unsubscribe = "退订检查", risks = "风险检查"
    var icon: String {
        switch self {
        case .all: return "tray.full"
        case .today: return "calendar.badge.clock"
        case .replies: return "arrowshape.turn.up.left.fill"
        case .unsubscribe: return "envelope.badge.minus"
        case .risks: return "exclamationmark.shield.fill"
        }
    }
    static func command(_ text: String) -> MailFilter? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "只看今天", "只看今天的邮件", "今日待办": return .today
        case "需要回复", "只看需要回复的邮件": return .replies
        case "退订检查": return .unsubscribe
        case "风险检查": return .risks
        case "全部邮件", "显示全部", "全部": return .all
        default: return nil
        }
    }
    func includes(_ message: MailMessage) -> Bool {
        switch self {
        case .all: return true
        case .today: return message.dueToday == true
        case .replies: return message.needsReply == true
        case .unsubscribe: return !message.unsubscribeUrls.isEmpty && message.risky != true
        case .risks: return message.risky == true
        }
    }
}

struct MailThread {
    var conversation: [ConversationItem] = []
    var draft = ""
}

struct MailWorkspace {
    var messages: [MailMessage] = []
    var selectedID: String?
    var threads: [String: MailThread] = [:]
    var selectedMessage: MailMessage? { messages.first { $0.cardID == selectedID } }
    var conversation: [ConversationItem] { selectedID.flatMap { threads[$0]?.conversation } ?? [] }
    var draft: String {
        get { selectedID.flatMap { threads[$0]?.draft } ?? "" }
        set {
            guard let id = selectedID else { return }
            threads[id, default: MailThread()].draft = newValue
        }
    }
    mutating func select(_ message: MailMessage) { selectedID = message.cardID }
    mutating func replaceMessages(_ updated: [MailMessage]) {
        messages = updated
        if !messages.contains(where: { $0.cardID == selectedID }) { selectedID = nil }
    }
    mutating func append(_ item: ConversationItem, to id: String) {
        threads[id, default: MailThread()].conversation.append(item)
    }
    func context(for id: String) -> String {
        // Keep whole turns, never a suffix cut through a prior message.
        var turns: [String] = []
        var length = 0
        for item in (threads[id]?.conversation ?? []).reversed() where item.role != .error {
            let turn = "\(item.role == .user ? "用户" : "助手")：\(item.text)"
            guard length + turn.count <= 12000, turns.count < 8 else { break }
            turns.insert(turn, at: 0)
            length += turn.count
        }
        return turns.joined(separator: "\n\n")
    }
}

struct AssistantError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

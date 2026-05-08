import Foundation

struct AssignedChore: Decodable, Identifiable {
    let assignedChoreId: String
    let choreId: String
    let userId: String
    let dueDate: String
    var status: ChoreStatus
    let choreName: String
    var description: String?
    let points: Int
    let difficulty: String
    var firstName: String?
    var completedAt: String?
    var transferredFrom: String?
    var transferType: String?
    var choreType: String?    // "daily_habit", "household", "routine", "personal_space", "laundry"
    var timeOfDay: String?    // "morning", "evening", "anytime"
    var minAge: Int?
    var autoApprove: Bool?

    var id: String { assignedChoreId }
    var isDailyHabit: Bool { choreType == "daily_habit" }
    var isAutoApprove: Bool { autoApprove == true }
    var isMorning: Bool { timeOfDay == "morning" || (isDailyHabit && (choreName.contains("(AM)") || choreName.contains("bed"))) }
    var isEvening: Bool { timeOfDay == "evening" || (isDailyHabit && (choreName.contains("(PM)") || choreName.contains("plate") || choreName.contains("laundry") || choreName.contains("Shower"))) }

    enum ChoreStatus: String, Codable {
        case pending, in_progress, completed, approved, rejected
    }

    // Support both camelCase (API) and snake_case (some endpoints)
    enum CodingKeys: String, CodingKey {
        case assignedChoreId, choreId, userId, dueDate, status, choreName, description
        case points, difficulty, firstName, completedAt, transferredFrom, transferType
        case choreType, timeOfDay, minAge, autoApprove
        // snake_case alternates
        case assigned_chore_id, chore_id, user_id, due_date, chore_name
        case first_name, completed_at, transferred_from, transfer_type
        case chore_type, time_of_day, min_age, auto_approve
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        assignedChoreId = (try? c.decodeStr(.assignedChoreId)) ?? (try? c.decodeStr(.assigned_chore_id)) ?? ""
        choreId = (try? c.decodeStr(.choreId)) ?? (try? c.decodeStr(.chore_id)) ?? ""
        userId = (try? c.decodeStr(.userId)) ?? (try? c.decodeStr(.user_id)) ?? ""
        dueDate = (try? c.decode(String.self, forKey: .dueDate)) ?? (try? c.decode(String.self, forKey: .due_date)) ?? ""
        status = (try? c.decode(ChoreStatus.self, forKey: .status)) ?? .pending
        choreName = (try? c.decode(String.self, forKey: .choreName)) ?? (try? c.decode(String.self, forKey: .chore_name)) ?? ""
        description = try? c.decode(String.self, forKey: .description)

        if let p = try? c.decode(Int.self, forKey: .points) { points = p }
        else if let s = try? c.decode(String.self, forKey: .points), let p = Int(s) { points = p }
        else { points = 0 }

        difficulty = (try? c.decode(String.self, forKey: .difficulty)) ?? "easy"
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? (try? c.decode(String.self, forKey: .first_name))
        completedAt = (try? c.decode(String.self, forKey: .completedAt)) ?? (try? c.decode(String.self, forKey: .completed_at))
        transferredFrom = (try? c.decode(String.self, forKey: .transferredFrom)) ?? (try? c.decode(String.self, forKey: .transferred_from))
        transferType = (try? c.decode(String.self, forKey: .transferType)) ?? (try? c.decode(String.self, forKey: .transfer_type))
        choreType = (try? c.decode(String.self, forKey: .choreType)) ?? (try? c.decode(String.self, forKey: .chore_type))
        timeOfDay = (try? c.decode(String.self, forKey: .timeOfDay)) ?? (try? c.decode(String.self, forKey: .time_of_day))
        minAge = (try? c.decode(Int.self, forKey: .minAge)) ?? (try? c.decode(Int.self, forKey: .min_age))
        autoApprove = (try? c.decode(Bool.self, forKey: .autoApprove)) ?? (try? c.decode(Bool.self, forKey: .auto_approve))
    }

    var difficultyTier: DifficultyTier {
        DifficultyTier(rawValue: difficulty) ?? .easy
    }
}

enum DifficultyTier: String, Codable {
    case easy, medium, hard

    var label: String {
        switch self {
        case .easy: return "Quick"
        case .medium: return "Standard"
        case .hard: return "Challenge"
        }
    }

    var emoji: String {
        switch self {
        case .easy: return "⚡"
        case .medium: return "🔧"
        case .hard: return "💪"
        }
    }
}

// MARK: - Helper for decoding String or Int as String
extension KeyedDecodingContainer {
    func decodeStr(_ key: Key) throws -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: ""))
    }
}

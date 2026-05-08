import Foundation

struct Badge: Decodable, Identifiable {
    let userId: String
    let firstName: String
    let weeklySuperstar: Bool
    let monthlyHero: Bool

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId, firstName, weeklySuperstar, monthlyHero
        case user_id, first_name, weekly_superstar, monthly_hero
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeStr(.userId)) ?? (try? c.decodeStr(.user_id)) ?? ""
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? (try? c.decode(String.self, forKey: .first_name)) ?? ""
        weeklySuperstar = (try? c.decode(Bool.self, forKey: .weeklySuperstar)) ?? (try? c.decode(Bool.self, forKey: .weekly_superstar)) ?? false
        monthlyHero = (try? c.decode(Bool.self, forKey: .monthlyHero)) ?? (try? c.decode(Bool.self, forKey: .monthly_hero)) ?? false
    }
}

struct LeaderboardEntry: Decodable, Identifiable {
    let rank: Int
    let userId: String
    let name: String
    let points: Int
    let avatarCustomizations: [String]

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case rank, userId, name, points, user_id, avatarCustomizations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = (try? c.decode(Int.self, forKey: .rank)) ?? 0
        userId = (try? c.decodeStr(.userId)) ?? (try? c.decodeStr(.user_id)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        if let p = try? c.decode(Int.self, forKey: .points) { points = p }
        else if let s = try? c.decode(String.self, forKey: .points), let p = Int(s) { points = p }
        else { points = 0 }
        avatarCustomizations = (try? c.decode([String].self, forKey: .avatarCustomizations)) ?? []
    }
}

struct UserStats: Decodable {
    let totalCompleted: Int
    let weekCompleted: Int
    let streak: Int
    let totalPoints: Int

    enum CodingKeys: String, CodingKey {
        case totalCompleted, weekCompleted, streak, totalPoints
        case total_completed, week_completed, total_points
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCompleted = (try? c.decode(Int.self, forKey: .totalCompleted)) ?? (try? c.decode(Int.self, forKey: .total_completed)) ?? 0
        weekCompleted = (try? c.decode(Int.self, forKey: .weekCompleted)) ?? (try? c.decode(Int.self, forKey: .week_completed)) ?? 0
        streak = (try? c.decode(Int.self, forKey: .streak)) ?? 0
        totalPoints = (try? c.decode(Int.self, forKey: .totalPoints)) ?? (try? c.decode(Int.self, forKey: .total_points)) ?? 0
    }
}

struct GameLevel {
    static let xpPerLevel = 100
    static func level(for points: Int) -> Int { max(1, points / xpPerLevel + 1) }
    static func xpInCurrentLevel(for points: Int) -> Int { points % xpPerLevel }
    static func xpProgress(for points: Int) -> Double { Double(xpInCurrentLevel(for: points)) / Double(xpPerLevel) }
    static func title(for level: Int) -> String {
        switch level {
        case 1...3: return "Apprentice"
        case 4...6: return "Adventurer"
        case 7...10: return "Hero"
        case 11...15: return "Champion"
        case 16...20: return "Legend"
        default: return "Mythic"
        }
    }
}

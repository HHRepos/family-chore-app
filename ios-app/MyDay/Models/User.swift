import Foundation

struct User: Codable, Identifiable {
    let userId: String
    var email: String?
    var firstName: String
    var lastName: String?
    var role: UserRole
    var familyId: String?
    var age: Int?
    var points: Int?
    var emoji: String?
    var participateInChores: Bool?

    var id: String { userId }

    enum UserRole: String, Codable {
        case parent, child
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case role
        case familyId = "family_id"
        case age, points, emoji
        case participateInChores = "participate_in_chores"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .userId) {
            userId = s
        } else if let i = try? c.decode(Int.self, forKey: .userId) {
            userId = String(i)
        } else { userId = "" }
        email = try? c.decode(String.self, forKey: .email)
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? ""
        lastName = try? c.decode(String.self, forKey: .lastName)
        role = (try? c.decode(UserRole.self, forKey: .role)) ?? .child
        if let s = try? c.decode(String.self, forKey: .familyId) {
            familyId = s
        } else if let i = try? c.decode(Int.self, forKey: .familyId) {
            familyId = String(i)
        } else { familyId = nil }
        age = try? c.decode(Int.self, forKey: .age)
        points = try? c.decode(Int.self, forKey: .points)
        emoji = try? c.decode(String.self, forKey: .emoji)
        participateInChores = try? c.decode(Bool.self, forKey: .participateInChores)
    }
}

struct LoginResponse: Codable {
    let token: String
    let userId: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? c.decode(String.self, forKey: .token)) ?? ""
        if let s = try? c.decode(String.self, forKey: .userId) {
            userId = s
        } else if let i = try? c.decode(Int.self, forKey: .userId) {
            userId = String(i)
        } else { userId = nil }
        email = try? c.decode(String.self, forKey: .email)
    }
}

struct ProfileResponse: Codable {
    let userId: String
    let email: String?
    let firstName: String
    let lastName: String?
    let role: String
    let familyId: String?
    var avatarCustomizations: [String]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case firstName = "first_name"
        case lastName = "last_name"
        case role
        case familyId = "family_id"
        case avatarCustomizations = "avatar_customizations"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .userId) {
            userId = s
        } else if let i = try? c.decode(Int.self, forKey: .userId) {
            userId = String(i)
        } else { userId = "" }
        email = try? c.decode(String.self, forKey: .email)
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? ""
        lastName = try? c.decode(String.self, forKey: .lastName)
        role = (try? c.decode(String.self, forKey: .role)) ?? "child"
        if let s = try? c.decode(String.self, forKey: .familyId) {
            familyId = s
        } else if let i = try? c.decode(Int.self, forKey: .familyId) {
            familyId = String(i)
        } else { familyId = nil }
        avatarCustomizations = (try? c.decode([String].self, forKey: .avatarCustomizations)) ?? []
    }
}

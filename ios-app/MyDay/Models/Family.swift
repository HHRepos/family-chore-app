import Foundation

struct Family: Decodable {
    let familyId: String
    let familyName: String
    var familyCode: String?
    var houseDetails: HouseDetails?
    var members: [FamilyMember]

    enum CodingKeys: String, CodingKey {
        case familyId = "family_id"
        case familyName = "family_name"
        case familyCode = "family_code"
        case houseDetails = "house_details"
        case members
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .familyId) {
            familyId = s
        } else if let i = try? c.decode(Int.self, forKey: .familyId) {
            familyId = String(i)
        } else { familyId = "" }
        familyName = (try? c.decode(String.self, forKey: .familyName)) ?? ""
        familyCode = try? c.decode(String.self, forKey: .familyCode)
        houseDetails = try? c.decode(HouseDetails.self, forKey: .houseDetails)
        members = (try? c.decode([FamilyMember].self, forKey: .members)) ?? []
    }
}

struct FamilyMember: Decodable, Identifiable {
    let userId: String
    let firstName: String
    var nickname: String?
    let role: String
    var age: Int?
    var hasAccount: Bool?
    var emoji: String?
    var participates: Bool?
    var avatarCustomizations: [String] = []

    var id: String { userId }

    var isChild: Bool { role == "child" }
    var isParent: Bool { role == "parent" }

    /// Counts as a chore-rotation participant: every child, plus parents who
    /// have opted in via the Settings toggle.
    var inChoreRotation: Bool { isChild || (isParent && participates == true) }

    enum CodingKeys: String, CodingKey {
        case userId, firstName, nickname, role, age, hasAccount, emoji, participates
        case user_id, first_name, has_account
        case avatarCustomizations = "avatar_customizations"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .userId) { userId = s }
        else if let s = try? c.decode(String.self, forKey: .user_id) { userId = s }
        else if let i = try? c.decode(Int.self, forKey: .userId) { userId = String(i) }
        else if let i = try? c.decode(Int.self, forKey: .user_id) { userId = String(i) }
        else { userId = "" }
        firstName = (try? c.decode(String.self, forKey: .firstName)) ?? (try? c.decode(String.self, forKey: .first_name)) ?? ""
        nickname = try? c.decode(String.self, forKey: .nickname)
        role = (try? c.decode(String.self, forKey: .role)) ?? "child"
        age = try? c.decode(Int.self, forKey: .age)
        hasAccount = (try? c.decode(Bool.self, forKey: .hasAccount)) ?? (try? c.decode(Bool.self, forKey: .has_account))
        emoji = try? c.decode(String.self, forKey: .emoji)
        participates = try? c.decode(Bool.self, forKey: .participates)
        avatarCustomizations = (try? c.decode([String].self, forKey: .avatarCustomizations)) ?? []
    }
}

struct HouseDetails: Codable {
    var scannedRooms: [ScannedRoom]?
    var binSchedule: BinSchedule?
    var pets: [Pet]?
    var gamingSchedule: [String: GamingConfig]?

    enum CodingKeys: String, CodingKey {
        case scannedRooms = "scanned_rooms"
        case binSchedule = "bin_schedule"
        case pets
        case gamingSchedule = "gaming_schedule"
    }
}

struct ScannedRoom: Codable {
    let name: String
    let confidence: Double?
    let assets: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        confidence = try? c.decode(Double.self, forKey: .confidence)
        assets = (try? c.decode([String].self, forKey: .assets)) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case name, confidence, assets
    }
}

struct BinSchedule: Codable {
    let collectionDays: [String]
    let rotationChildren: [String]
    let rotationWeekStart: String?

    enum CodingKeys: String, CodingKey {
        case collectionDays = "collection_days"
        case rotationChildren = "rotation_children"
        case rotationWeekStart = "rotation_week_start"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectionDays = (try? c.decode([String].self, forKey: .collectionDays)) ?? []
        // Handle both String and Int arrays for rotation children
        if let strings = try? c.decode([String].self, forKey: .rotationChildren) {
            rotationChildren = strings
        } else if let ints = try? c.decode([Int].self, forKey: .rotationChildren) {
            rotationChildren = ints.map { String($0) }
        } else { rotationChildren = [] }
        rotationWeekStart = try? c.decode(String.self, forKey: .rotationWeekStart)
    }
}

struct Pet: Codable, Identifiable {
    let id: String
    let name: String
    let type: String
    var walkRotationChildren: [String]?
    var litterRotationChildren: [String]?
    var walkDays: [String]?
    var litterDays: [String]?
    var minWalkAge: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case walkRotationChildren = "walk_rotation_children"
        case litterRotationChildren = "litter_rotation_children"
        case walkDays = "walk_days"
        case litterDays = "litter_days"
        case minWalkAge = "min_walk_age"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else { id = UUID().uuidString }
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""

        if let strings = try? c.decode([String].self, forKey: .walkRotationChildren) {
            walkRotationChildren = strings
        } else if let ints = try? c.decode([Int].self, forKey: .walkRotationChildren) {
            walkRotationChildren = ints.map { String($0) }
        }

        if let strings = try? c.decode([String].self, forKey: .litterRotationChildren) {
            litterRotationChildren = strings
        } else if let ints = try? c.decode([Int].self, forKey: .litterRotationChildren) {
            litterRotationChildren = ints.map { String($0) }
        }

        walkDays = try? c.decode([String].self, forKey: .walkDays)
        litterDays = try? c.decode([String].self, forKey: .litterDays)
        minWalkAge = try? c.decode(Int.self, forKey: .minWalkAge)
    }
}

struct GamingConfig: Codable {
    let rules: [GamingRule]
}

struct GamingRule: Codable {
    let days: [String]
    let device: String
    let hours: Double
}

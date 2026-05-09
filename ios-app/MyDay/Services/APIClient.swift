import Foundation

enum HTTPMethod: String {
    case GET, POST, PATCH, PUT, DELETE
}

enum APIError: LocalizedError {
    case unauthorized
    case badRequest(String)
    case serverError(String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Session expired. Please log in again."
        case .badRequest(let msg): return msg
        case .serverError(let msg): return msg
        case .decodingError(let msg): return "Data error: \(msg)"
        case .networkError(let msg): return msg
        }
    }
}

final class APIClient: Sendable {
    static let shared = APIClient()

    private let baseURL = "https://54-171-244-65.nip.io/v1"
    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    // MARK: - Core Request

    func request<T: Decodable>(_ method: HTTPMethod, _ path: String, body: (any Encodable)? = nil) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.networkError("Invalid URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        if let token = KeychainHelper.getToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        if http.statusCode >= 400 {
            // Always check response body for error message first
            if let err = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = err["error"] {
                if http.statusCode == 401 && msg == "Invalid credentials" {
                    throw APIError.badRequest("Invalid email or password")
                }
                throw http.statusCode == 401 ? APIError.unauthorized : APIError.badRequest(msg)
            }
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError("Error \(http.statusCode)")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    // Fire-and-forget version for endpoints that return simple messages
    func requestVoid(_ method: HTTPMethod, _ path: String, body: (any Encodable)? = nil) async throws {
        let _: [String: String] = try await request(method, path, body: body)
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> LoginResponse {
        try await request(.POST, "/auth/login", body: ["email": email, "password": password])
    }

    func register(email: String, password: String, firstName: String, lastName: String, role: String = "parent") async throws -> LoginResponse {
        try await request(.POST, "/auth/register", body: [
            "email": email, "password": password,
            "first_name": firstName, "last_name": lastName, "role": role
        ])
    }

    func getProfile() async throws -> ProfileResponse {
        try await request(.GET, "/auth/profile")
    }

    // MARK: - Family

    func getFamily(_ familyId: String) async throws -> Family {
        try await request(.GET, "/families/\(familyId)")
    }

    func createFamily(name: String, houseType: String) async throws -> [String: String] {
        try await request(.POST, "/families", body: ["family_name": name, "house_type": houseType])
    }

    func joinFamily(code: String, role: String) async throws -> [String: String] {
        try await request(.POST, "/families/join", body: ["family_code": code, "role": role])
    }

    func addFamilyMember(_ familyId: String, firstName: String, age: Int, role: String = "child") async throws {
        let _: [String: String] = try await request(.POST, "/families/\(familyId)/members", body: [
            "first_name": firstName, "age": String(age), "role": role
        ])
    }

    func updateFamilyConfig(_ familyId: String, config: [String: Any]) async throws {
        guard let url = URL(string: baseURL + "/families/\(familyId)/config") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.getToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: config)
        let _ = try await session.data(for: req)
    }

    // MARK: - Rooms (AI Scanning)

    func addRoomsAndChores(_ familyId: String, rooms: [[String: Any]]) async throws {
        guard let url = URL(string: baseURL + "/families/\(familyId)/rooms") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.getToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["rooms": rooms])
        let _ = try await session.data(for: req)
    }

    func analyzeRoom(imageBase64: String) async throws -> [[String: Any]] {
        guard let url = URL(string: baseURL + "/ai/analyze-room") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.getToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["image": imageBase64])
        let (data, _) = try await session.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rooms = json["rooms"] as? [[String: Any]] {
            return rooms
        }
        return []
    }

    // MARK: - Chores

    func getUserChores(_ userId: String) async throws -> [AssignedChore] {
        try await request(.GET, "/users/\(userId)/chores")
    }

    func getFamilyChores(_ familyId: String) async throws -> [AssignedChore] {
        try await request(.GET, "/families/\(familyId)/chores")
    }

    func createChore(_ familyId: String, name: String, description: String, frequency: String, difficulty: String, points: Int) async throws {
        let _: [String: String] = try await request(.POST, "/chores", body: [
            "family_id": familyId, "chore_name": name, "description": description,
            "frequency": frequency, "difficulty": difficulty, "points": String(points)
        ])
    }

    func updateChoreStatus(_ assignedChoreId: String, status: String) async throws {
        let _: [String: String] = try await request(.PATCH, "/chores/assigned/\(assignedChoreId)", body: ["status": status])
    }

    func approveChore(_ assignedChoreId: String) async throws {
        let _: [String: String] = try await request(.POST, "/chores/assigned/\(assignedChoreId)/approve")
    }

    func rejectChore(_ assignedChoreId: String) async throws {
        let _: [String: String] = try await request(.PATCH, "/chores/assigned/\(assignedChoreId)", body: ["status": "rejected"])
    }

    func transferChore(_ assignedChoreId: String, toUserId: String) async throws {
        let _: [String: String] = try await request(.POST, "/chores/assigned/\(assignedChoreId)/transfer", body: ["to_user_id": toUserId])
    }

    func requestSupport(_ assignedChoreId: String, helperUserId: String) async throws {
        let _: [String: String] = try await request(.POST, "/chores/assigned/\(assignedChoreId)/support", body: ["helper_user_id": helperUserId])
    }

    // MARK: - Stats & Gamification

    func getUserStats(_ userId: String) async throws -> UserStats {
        try await request(.GET, "/users/\(userId)/stats")
    }

    func getUserPoints(_ userId: String) async throws -> [String: Int] {
        try await request(.GET, "/users/\(userId)/points")
    }

    func getBadges(_ familyId: String) async throws -> [Badge] {
        try await request(.GET, "/families/\(familyId)/badges")
    }

    func getLeaderboard(_ familyId: String) async throws -> [LeaderboardEntry] {
        try await request(.GET, "/families/\(familyId)/leaderboard")
    }

    func getPendingApprovals(_ familyId: String) async throws -> [AssignedChore] {
        try await request(.GET, "/families/\(familyId)/approvals")
    }

    // MARK: - Rewards

    func getRewards(_ familyId: String) async throws -> [Reward] {
        try await request(.GET, "/families/\(familyId)/rewards")
    }

    func createReward(_ familyId: String, name: String, description: String, pointCost: Int, childId: String?) async throws {
        var body: [String: String] = [
            "family_id": familyId, "reward_name": name,
            "description": description, "point_cost": String(pointCost)
        ]
        if let childId { body["child_id"] = childId }
        let _: [String: String] = try await request(.POST, "/rewards", body: body)
    }

    func bulkCreateRewards(_ rewards: [[String: String]]) async throws {
        let _: [String: String] = try await request(.POST, "/rewards/bulk", body: ["rewards": rewards])
    }

    func updateReward(_ rewardId: String, name: String, description: String, pointCost: Int) async throws {
        let _: [String: String] = try await request(.PATCH, "/rewards/\(rewardId)", body: [
            "reward_name": name, "description": description, "point_cost": String(pointCost)
        ])
    }

    func deleteReward(_ rewardId: String) async throws {
        let _: [String: String] = try await request(.DELETE, "/rewards/\(rewardId)")
    }

    func redeemReward(userId: String, rewardId: String) async throws {
        let _: [String: String] = try await request(.POST, "/rewards/redeem", body: ["user_id": userId, "reward_id": rewardId])
    }

    // MARK: - Jobs

    func getJobs(_ familyId: String) async throws -> [Job] {
        try await request(.GET, "/families/\(familyId)/jobs")
    }

    func createJob(_ familyId: String, title: String, description: String, rewardType: String, rewardAmount: Double, jobType: String, dueDate: String?) async throws {
        var body: [String: String] = [
            "family_id": familyId, "title": title, "description": description,
            "reward_type": rewardType, "reward_amount": String(rewardAmount), "job_type": jobType
        ]
        if let dueDate { body["due_date"] = dueDate }
        let _: [String: String] = try await request(.POST, "/jobs", body: body)
    }

    func applyToJob(_ jobId: String, reason: String?, bidAmount: Double?) async throws {
        var body: [String: String] = [:]
        if let reason { body["reason"] = reason }
        if let bidAmount { body["bid_amount"] = String(bidAmount) }
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/apply", body: body)
    }

    func getJobApplications(_ jobId: String) async throws -> [JobApplication] {
        try await request(.GET, "/jobs/\(jobId)/applications")
    }

    func assignJob(_ jobId: String, applicationId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/assign", body: ["application_id": applicationId])
    }

    func completeJob(_ jobId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/complete")
    }

    func confirmJob(_ jobId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/confirm")
    }

    // MARK: - Screen Time

    func getScreenTime(_ userId: String) async throws -> ScreenTimeSettings {
        try await request(.GET, "/users/\(userId)/screen-time")
    }

    func updateScreenTime(_ userId: String, settings: ScreenTimeSettings) async throws {
        let _: [String: String] = try await request(.PUT, "/users/\(userId)/screen-time", body: settings)
    }

    func getScreenTimeAccess(_ userId: String) async throws -> ScreenTimeAccess {
        try await request(.GET, "/users/\(userId)/screen-time/access")
    }

    // MARK: - Invitations

    func createChildInvitation(_ childId: String) async throws -> [String: String] {
        try await request(.POST, "/children/\(childId)/invite")
    }

    func validateInvitation(_ token: String) async throws -> [String: String] {
        try await request(.GET, "/invitations/\(token)")
    }

    func claimInvitation(_ token: String, email: String, password: String) async throws -> LoginResponse {
        try await request(.POST, "/invitations/\(token)/claim", body: ["email": email, "password": password])
    }

    // Short invite code endpoints
    func validateInviteCode(_ code: String) async throws -> InviteCodeValidation {
        try await request(.GET, "/invitations/code/\(code)")
    }

    func claimInviteCode(_ code: String, email: String, password: String) async throws -> LoginResponse {
        try await request(.POST, "/invitations/code/\(code)/claim", body: ["email": email, "password": password])
    }

    // MARK: - Participation

    func getParticipation(_ userId: String) async throws -> [String: Bool] {
        try await request(.GET, "/users/\(userId)/participate")
    }

    func setParticipation(_ userId: String, participate: Bool) async throws {
        let _: [String: String] = try await request(.PATCH, "/users/\(userId)/participate", body: ["participate": participate ? "true" : "false"])
    }

    struct AvatarUpdateBody: Encodable { let customizations: [String] }
    struct AvatarUpdateResponse: Decodable {
        let user_id: String
        let avatar_customizations: [String]
    }
    func updateAvatar(_ userId: String, customizations: [String]) async throws {
        let _: AvatarUpdateResponse = try await request(
            .PATCH,
            "/users/\(userId)/avatar",
            body: AvatarUpdateBody(customizations: customizations)
        )
    }

    func getSkills(_ userId: String) async throws -> [Skill] {
        let resp: SkillsResponse = try await request(.GET, "/users/\(userId)/skills")
        return resp.skills
    }

    func updateFamily(_ familyId: String, name: String?, houseType: String?) async throws {
        var body: [String: String] = [:]
        if let name { body["family_name"] = name }
        if let houseType { body["house_type"] = houseType }
        let _: [String: String] = try await request(.PATCH, "/families/\(familyId)", body: body)
    }

    func deleteFamily(_ familyId: String) async throws -> [String: String] {
        try await request(.DELETE, "/families/\(familyId)")
    }

    func removeFamilyMember(_ familyId: String, memberId: String) async throws -> [String: String] {
        try await request(.DELETE, "/families/\(familyId)/members/\(memberId)")
    }

    // MARK: - Child Link Code (exploring kid invites parent)

    func generateLinkCode() async throws -> [String: String] {
        try await request(.POST, "/auth/generate-link-code")
    }

    func linkChildToFamily(linkCode: String) async throws -> [String: String] {
        try await request(.POST, "/families/link-child", body: ["link_code": linkCode])
    }

    // MARK: - Contract Proposals (Kid-Initiated)

    func pitchContract(_ familyId: String, title: String, description: String, rewardType: String, proposedPrice: Double, pitchReason: String, dueDate: String? = nil) async throws {
        var body: [String: String] = [
            "family_id": familyId, "title": title, "description": description,
            "reward_type": rewardType, "reward_amount": String(proposedPrice),
            "job_type": "open", "pitch_reason": pitchReason, "proposed_price": String(proposedPrice)
        ]
        if let dueDate, !dueDate.isEmpty { body["due_date"] = dueDate }
        let _: [String: String] = try await request(.POST, "/jobs", body: body)
    }

    func approveProposal(_ jobId: String, adjustedAmount: Double? = nil) async throws {
        var body: [String: String] = [:]
        if let amt = adjustedAmount { body["adjusted_amount"] = String(amt) }
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/approve-proposal", body: body)
    }

    func rejectProposal(_ jobId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/reject-proposal")
    }

    // MARK: - Negotiation

    func counterOffer(_ jobId: String, applicationId: String, amount: Double, message: String?) async throws {
        var body: [String: String] = ["amount": String(amount)]
        if let msg = message { body["message"] = msg }
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/applications/\(applicationId)/counter", body: body)
    }

    func acceptCounter(_ jobId: String, applicationId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/applications/\(applicationId)/accept-counter")
    }

    // MARK: - Subcontracting

    func createSubcontract(_ jobId: String, subcontractorId: String, amount: Double, taskDescription: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/subcontract", body: [
            "subcontractor_id": subcontractorId, "amount": String(amount), "task_description": taskDescription
        ])
    }

    func acceptSubcontract(_ jobId: String, subcontractId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/subcontract/\(subcontractId)/accept")
    }

    func completeSubcontract(_ jobId: String, subcontractId: String) async throws {
        let _: [String: String] = try await request(.POST, "/jobs/\(jobId)/subcontract/\(subcontractId)/complete")
    }

    func getSubcontracts(_ jobId: String) async throws -> [Subcontract] {
        try await request(.GET, "/jobs/\(jobId)/subcontracts")
    }

    // MARK: - Contract Portfolio

    func getContractStats(_ userId: String) async throws -> ContractPortfolio {
        try await request(.GET, "/users/\(userId)/contract-stats")
    }

    // MARK: - AI

    func distributeChores(_ familyId: String) async throws {
        let _: [String: String] = try await request(.POST, "/ai/families/\(familyId)/distribute-chores")
    }

    /// Conversational voice/text onboarding with GPT
    func voiceSetup(sessionId: String?, textInput: String, conversationHistory: [[String: String]] = []) async throws -> VoiceSetupResponse {
        guard let url = URL(string: baseURL + "/ai/voice-setup") else { throw APIError.networkError("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.getToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body: [String: Any] = [:]
        if let sessionId { body["session_id"] = sessionId }
        body["text_input"] = textInput
        if !conversationHistory.isEmpty { body["conversation_history"] = conversationHistory }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw APIError.serverError("Voice setup failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decodingError("Invalid response")
        }

        let sid = json["session_id"] as? String ?? ""
        let message = json["message"] as? String ?? ""
        let isComplete = json["is_complete"] as? Bool ?? false

        var extractedData = ExtractedFamilyData()
        if let ed = json["extracted_data"] as? [String: Any] {
            extractedData.familyName = ed["family_name"] as? String
            extractedData.houseType = ed["house_type"] as? String
            if let kids = ed["children"] as? [[String: Any]] {
                extractedData.children = kids.map { k in
                    ExtractedChild(name: k["name"] as? String ?? "", age: k["age"] as? Int ?? 0)
                }
            }
            if let bs = ed["bin_schedule"] as? [String: Any] {
                var bins: [ExtractedBin] = []
                if let binsArr = bs["bins"] as? [[String: Any]] {
                    bins = binsArr.map { b in
                        ExtractedBin(
                            type: b["type"] as? String ?? "",
                            collectionDay: b["collection_day"] as? String ?? "",
                            frequency: b["frequency"] as? String ?? "weekly"
                        )
                    }
                }
                extractedData.binSchedule = ExtractedBinSchedule(
                    bins: bins,
                    rotation: bs["rotation"] as? String,
                    rotationPerson: bs["rotation_person"] as? String
                )
            }
            if let pets = ed["pets"] as? [[String: Any]] {
                extractedData.pets = pets.map { p in
                    ExtractedPet(
                        name: p["name"] as? String ?? "",
                        type: p["type"] as? String ?? "",
                        careTasks: p["care_tasks"] as? [String] ?? []
                    )
                }
            }
        }

        let readyForRoomScan = json["ready_for_room_scan"] as? Bool ?? false
        return VoiceSetupResponse(sessionId: sid, message: message, isComplete: isComplete, readyForRoomScan: readyForRoomScan, extractedData: extractedData)
    }

    /// Text-to-speech — returns audio data
    func textToSpeech(_ text: String) async throws -> Data {
        guard let url = URL(string: baseURL + "/ai/tts") else { throw APIError.networkError("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.getToken() { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw APIError.serverError("TTS failed")
        }
        return data
    }
}

// MARK: - Voice Setup Models
struct InviteCodeValidation: Decodable {
    let valid: Bool
    let childName: String?
    let familyName: String?
    let inviteCode: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case valid, inviteCode, expiresAt
        case childName = "child_name"
        case familyName = "family_name"
        case invite_code, expires_at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        valid = (try? c.decode(Bool.self, forKey: .valid)) ?? false
        childName = (try? c.decode(String.self, forKey: .childName)) ?? (try? c.decode(String.self, forKey: .childName))
        familyName = (try? c.decode(String.self, forKey: .familyName)) ?? (try? c.decode(String.self, forKey: .familyName))
        inviteCode = (try? c.decode(String.self, forKey: .inviteCode)) ?? (try? c.decode(String.self, forKey: .invite_code))
        expiresAt = (try? c.decode(String.self, forKey: .expiresAt)) ?? (try? c.decode(String.self, forKey: .expires_at))
    }
}

struct VoiceSetupResponse {
    let sessionId: String
    let message: String
    let isComplete: Bool
    let readyForRoomScan: Bool
    let extractedData: ExtractedFamilyData
}

struct ExtractedFamilyData {
    var familyName: String?
    var houseType: String?
    var children: [ExtractedChild] = []
    var binSchedule: ExtractedBinSchedule?
    var pets: [ExtractedPet]?
}

struct ExtractedChild {
    let name: String
    let age: Int
}

struct ExtractedBinSchedule {
    let bins: [ExtractedBin]
    let rotation: String? // "children", "family", "specific_person"
    let rotationPerson: String?
}

struct ExtractedBin {
    let type: String // "waste", "recycling", "garden", "food_waste"
    let collectionDay: String
    let frequency: String // "weekly", "fortnightly"
}

struct ExtractedPet {
    let name: String
    let type: String // "dog", "cat", etc.
    let careTasks: [String] // ["walk", "feed", "litter"]
}

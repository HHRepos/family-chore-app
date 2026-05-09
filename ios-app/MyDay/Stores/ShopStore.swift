import Foundation
import Observation

@Observable
class ShopStore {
    var rewards: [Reward] = []
    var leaderboard: [LeaderboardEntry] = []
    var badges: [Badge] = []
    var stats: UserStats?
    var points: Int = 0
    var skills: [Skill] = []
    var isLoading = false

    var level: Int { GameLevel.level(for: points) }
    var xpProgress: Double { GameLevel.xpProgress(for: points) }
    var levelTitle: String { GameLevel.title(for: level) }

    func loadAll(userId: String, familyId: String) async {
        isLoading = true
        async let r = APIClient.shared.getRewards(familyId)
        async let l = APIClient.shared.getLeaderboard(familyId)
        async let b = APIClient.shared.getBadges(familyId)
        async let s = APIClient.shared.getUserStats(userId)
        async let p = APIClient.shared.getUserPoints(userId)
        async let sk = APIClient.shared.getSkills(userId)

        do {
            rewards = try await r
            leaderboard = try await l
            badges = try await b
            stats = try await s
            let pts = try await p
            points = pts["points"] ?? 0
            skills = (try? await sk) ?? []
        } catch {
            print("Failed to load shop data: \(error)")
        }
        isLoading = false
    }

    func redeemReward(_ reward: Reward, userId: String) async -> Bool {
        guard points >= reward.pointCost else { return false }
        do {
            try await APIClient.shared.redeemReward(userId: userId, rewardId: reward.rewardId)
            points -= reward.pointCost
            return true
        } catch {
            return false
        }
    }
}

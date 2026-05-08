import SwiftUI

struct LeaderboardView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ShopStore.self) private var shop

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.neonYellow)
                            .neonGlow(.neonYellow, radius: 16)

                        Text("Rankings")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 16)

                    if shop.leaderboard.isEmpty {
                        Text("No rankings yet")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 40)
                    } else {
                        ForEach(shop.leaderboard) { entry in
                            HStack(spacing: 14) {
                                // Rank
                                ZStack {
                                    Circle()
                                        .fill(entry.rank == 1 ? Color.neonYellow :
                                                entry.rank == 2 ? Color.gray :
                                                entry.rank == 3 ? Color.neonOrange : Color.gameCardLight)
                                        .frame(width: 32, height: 32)
                                    Text("\(entry.rank)")
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(entry.rank <= 3 ? .black : .white.opacity(0.5))
                                }

                                AvatarView(
                                    seed: entry.userId,
                                    size: 36,
                                    customizations: entry.avatarCustomizations,
                                    fallbackInitial: entry.name
                                )

                                // Name
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Level \(GameLevel.level(for: entry.points))")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.4))
                                }

                                Spacer()

                                // Points
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.neonYellow)
                                    Text("\(entry.points)")
                                        .font(.system(size: 16, weight: .black, design: .rounded))
                                        .foregroundStyle(.neonYellow)
                                }
                            }
                            .gameCard(glow: entry.rank == 1 ? .neonYellow : .clear)
                        }
                    }
                }
                .padding(16)
            }
        }
        .task {
            if let familyId = auth.familyId {
                do {
                    shop.leaderboard = try await APIClient.shared.getLeaderboard(familyId)
                } catch {}
            }
        }
    }
}

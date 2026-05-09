import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ShopStore.self) private var shop
    @State private var showLogoutConfirm = false
    @State private var showPortfolio = false
    @State private var showAvatarConfig = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Avatar + Level
                    VStack(spacing: 12) {
                        Button { showAvatarConfig = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(
                                    seed: auth.userId ?? "fallback",
                                    size: 160,
                                    customizations: auth.user?.avatarCustomizations ?? [],
                                    fallbackInitial: auth.user?.firstName
                                )
                                .neonGlow(.neonPurple, radius: 16)

                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.neonPurple)
                                    .background(Circle().fill(Color.gameBackground).padding(2))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.plain)

                        Text(auth.user?.firstName ?? "Hero")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Level \(shop.level) \(shop.levelTitle)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.neonPurple)

                        Button("Customize avatar") { showAvatarConfig = true }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.neonPurple)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Color.neonPurple.opacity(0.12))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonPurple.opacity(0.3), lineWidth: 1))
                    }
                    .padding(.top, 20)
                    .sheet(isPresented: $showAvatarConfig) {
                        AvatarConfigView(
                            userId: auth.userId ?? "",
                            initialCustomizations: auth.user?.avatarCustomizations ?? [],
                            onSaved: { newConfig in
                                auth.user?.avatarCustomizations = newConfig
                            }
                        )
                    }

                    // XP Bar
                    XPBar(points: shop.points)
                        .padding(.horizontal, 4)
                        .gameCard(glow: .neonGreen)

                    // Stats
                    HStack(spacing: 12) {
                        StatBox(value: "\(shop.stats?.totalCompleted ?? 0)", label: "All Time", icon: "checkmark.circle.fill", color: .neonGreen)
                        StatBox(value: "\(shop.stats?.weekCompleted ?? 0)", label: "This Week", icon: "calendar", color: .neonBlue)
                        StatBox(value: "\(shop.points)", label: "Points", icon: "star.fill", color: .neonYellow)
                    }

                    // Streak
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.neonOrange)
                            Text("Streak")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(shop.stats?.streak ?? 0) days")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.neonOrange)
                        }
                        StreakMeter(streak: shop.stats?.streak ?? 0)
                    }
                    .gameCard(glow: .neonOrange)

                    // Skills & qualities — derived from chore + job activity.
                    // Six skills laid out 2-up: Discipline, Responsibility,
                    // Initiative, Reliability, Teamwork, Entrepreneurship.
                    if !shop.skills.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.neonPurple)
                                Text("Skills & qualities")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(shop.skills) { skill in
                                    SkillCard(skill: skill)
                                }
                            }
                        }
                    }

                    // Weekly Progress Badges
                    WeeklyBadgesSection(weekCompleted: shop.stats?.weekCompleted ?? 0)

                    // Streak Badges
                    StreakBadgesSection(streak: shop.stats?.streak ?? 0)

                    // Status Badges
                    if let badge = shop.badges.first(where: { $0.userId == auth.userId }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Status Badges")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            BadgeGrid(weeklySuperstar: badge.weeklySuperstar, monthlyHero: badge.monthlyHero)
                        }
                        .gameCard(glow: .neonPurple)
                    }

                    // Business Portfolio
                    Button { showPortfolio = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "briefcase.fill").font(.system(size: 18)).foregroundStyle(.neonBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("My Business Portfolio").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                Text("Contracts, earnings, reliability").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.2))
                        }.gameCard(glow: .neonBlue.opacity(0.2))
                    }.buttonStyle(.plain)

                    // Logout
                    Button("Log Out") { showLogoutConfirm = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 20)

                    Text("Version 1.0.0")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.2))
                }
                .padding(16)
            }
        }
        .task {
            if let userId = auth.userId, let familyId = auth.familyId {
                await shop.loadAll(userId: userId, familyId: familyId)
            }
        }
        .sheet(isPresented: $showPortfolio) { BusinessPortfolioView() }
        .alert("Log Out", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { auth.fullLogout() }
        } message: {
            Text("Are you sure you want to log out?")
        }
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .gameCard(glow: color)
    }
}

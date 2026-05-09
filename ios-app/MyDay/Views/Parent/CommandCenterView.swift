import SwiftUI

struct CommandCenterView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLeaderboard = false
    @State private var showRules = false
    @State private var showScreenTime = false
    @State private var showAllChores = false
    @State private var showManageFamily = false
    @State private var isRedistributing = false

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f.string(from: Date())
    }

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header — the decorative 2x2 grid icon was removed in
                    // Build 13 ("4 squares" testers tapped expecting an action).
                    HStack(spacing: 12) {
                        AvatarView(
                            seed: auth.userId ?? "parent",
                            size: 56,
                            customizations: auth.user?.avatarCustomizations ?? [],
                            fallbackInitial: auth.user?.firstName
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedDate)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("Command Center")
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text(familyStore.family?.familyName ?? "")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Quick Stats
                    HStack(spacing: 12) {
                        QuickStat(
                            value: "\(choreStore.todaysChores.count)",
                            label: "Today's\nQuests",
                            icon: "scroll.fill",
                            color: .neonBlue
                        )
                        QuickStat(
                            value: "\(choreStore.pendingApprovals.count)",
                            label: "Pending\nApproval",
                            icon: "checkmark.seal.fill",
                            color: .neonOrange
                        )
                        QuickStat(
                            value: "\(familyStore.children.count)",
                            label: "Family\nMembers",
                            icon: "person.3.fill",
                            color: .neonPurple
                        )
                    }

                    // Quick action buttons
                    HStack(spacing: 10) {
                        Button { showLeaderboard = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trophy.fill").font(.system(size: 14))
                                Text("Rankings").font(.system(size: 12, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonYellow)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.neonYellow.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonYellow.opacity(0.3), lineWidth: 1))
                        }
                        Button { showRules = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "book.closed.fill").font(.system(size: 14))
                                Text("Rules").font(.system(size: 12, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonBlue)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.neonBlue.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonBlue.opacity(0.3), lineWidth: 1))
                        }
                        Button { showScreenTime = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tv.fill").font(.system(size: 14))
                                Text("Screen").font(.system(size: 12, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonGreen)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.neonGreen.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonGreen.opacity(0.3), lineWidth: 1))
                        }
                    }

                    // My chores today — shown when this parent participates in
                    // the rotation. Filters family chores to the parent's own
                    // user_id so they can see and complete their slice without
                    // leaving the dashboard.
                    let myChoresToday = choreStore.chores.filter {
                        $0.userId == auth.userId && String($0.dueDate.prefix(10)) == todayString
                    }
                    if !myChoresToday.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("My chores today", systemImage: "person.badge.shield.checkmark.fill")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.neonPurple)
                                Spacer()
                                Text("\(myChoresToday.filter { $0.status == .approved || $0.status == .completed }.count) / \(myChoresToday.count) done")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            ForEach(myChoresToday) { chore in
                                HStack(spacing: 10) {
                                    Image(systemName: chore.status == .approved ? "checkmark.seal.fill" :
                                          chore.status == .completed ? "hourglass" : "circle")
                                        .foregroundStyle(chore.status == .approved ? .neonGreen :
                                                         chore.status == .completed ? .neonBlue : .white.opacity(0.3))
                                    Text(chore.choreName)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                        .strikethrough(chore.status == .approved)
                                    Spacer()
                                    Text("\(chore.points) pts")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(.neonYellow.opacity(0.7))
                                }
                                .padding(10)
                                .background(Color.gameCardLight)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }.gameCard(glow: .neonPurple.opacity(0.3))
                    }

                    // Invite children card (if children exist without accounts)
                    let childrenWithoutAccounts = familyStore.children.filter { $0.hasAccount != true }
                    if !childrenWithoutAccounts.isEmpty {
                        Button { showManageFamily = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.badge.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.neonGreen)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(childrenWithoutAccounts.count) child\(childrenWithoutAccounts.count > 1 ? "ren" : "") without accounts")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text("Tap to manage & generate invite codes")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.2))
                            }
                            .gameCard(glow: .neonGreen.opacity(0.3))
                        }.buttonStyle(.plain)
                    }

                    // All Chores link
                    Button { showAllChores = true } label: {
                        HStack {
                            Image(systemName: "list.bullet.rectangle.fill").foregroundStyle(.neonBlue)
                            Text("View All Chores").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.2))
                        }.gameCard(glow: .neonBlue.opacity(0.2))
                    }.buttonStyle(.plain)

                    // Children overview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Family Members")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        ForEach(familyStore.children) { child in
                            let childChores = choreStore.chores.filter {
                                $0.userId == child.userId && String($0.dueDate.prefix(10)) == todayString
                            }
                            let done = childChores.filter { $0.status == .completed || $0.status == .approved }.count

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(Color.neonPurple.opacity(0.2)).frame(width: 40, height: 40)
                                        Text(child.firstName.prefix(1).uppercased())
                                            .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(child.firstName).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        Text("\(done)/\(childChores.count) quests done").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    if let entry = shop.leaderboard.first(where: { $0.userId == child.userId }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.neonYellow)
                                            Text("\(entry.points)").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                        }
                                    }
                                }
                                // Per-chore status dots
                                if !childChores.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(childChores) { chore in
                                            HStack(spacing: 8) {
                                                Circle().fill(choreStatusColor(chore.status)).frame(width: 8, height: 8)
                                                Text(chore.choreName).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                                                Spacer()
                                                Text("\(chore.points)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow.opacity(0.6))
                                            }
                                        }
                                    }
                                    .padding(.leading, 52)
                                }
                            }
                            .gameCard(glow: .neonPurple.opacity(0.3))
                        }
                    }

                    // Badges
                    if !shop.badges.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Badges")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            ForEach(shop.badges) { badge in
                                HStack(spacing: 12) {
                                    Text(badge.firstName)
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if badge.weeklySuperstar {
                                        HStack(spacing: 3) {
                                            Image(systemName: "shield.fill").font(.system(size: 14)).foregroundStyle(.gray)
                                            Text("Superstar").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.gray)
                                        }
                                    }
                                    if badge.monthlyHero {
                                        HStack(spacing: 3) {
                                            Image(systemName: "medal.fill").font(.system(size: 14)).foregroundStyle(.neonYellow)
                                            Text("Hero").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                        }
                                    }
                                }
                                .gameCard()
                            }
                        }
                    }

                    // Distribute chores button
                    Button {
                        isRedistributing = true
                        Task {
                            guard let fid = auth.familyId else { return }
                            try? await APIClient.shared.distributeChores(fid)
                            await choreStore.loadFamilyChores(familyId: fid)
                            isRedistributing = false
                        }
                    } label: {
                        if isRedistributing {
                            ProgressView().tint(.white)
                        } else {
                            Label("Redistribute Quests", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(NeonButtonStyle(color: .neonPurple))
                    .disabled(isRedistributing)
                }
                .padding(16)
            }
            .refreshable {
                if let fid = auth.familyId {
                    await choreStore.loadFamilyChores(familyId: fid)
                    await choreStore.loadApprovals(familyId: fid)
                    if let uid = auth.userId {
                        await shop.loadAll(userId: uid, familyId: fid)
                    }
                }
            }
        }
        .task {
            if let fid = auth.familyId, let uid = auth.userId {
                await shop.loadAll(userId: uid, familyId: fid)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Refresh on app foreground so the parent sees up-to-date
            // approvals + family chore counts when they come back.
            guard newPhase == .active else { return }
            Task {
                if let fid = auth.familyId, let uid = auth.userId {
                    await choreStore.loadFamilyChores(familyId: fid)
                    await choreStore.loadApprovals(familyId: fid)
                    await shop.loadAll(userId: uid, familyId: fid)
                }
            }
        }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView() }
        .sheet(isPresented: $showRules) { FamilyRulesView() }
        .sheet(isPresented: $showScreenTime) { ScreenTimeView() }
        .sheet(isPresented: $showAllChores) { AllChoresView() }
        .sheet(isPresented: $showManageFamily) { ManageFamilyView() }
    }

    private func choreStatusColor(_ status: AssignedChore.ChoreStatus) -> Color {
        switch status {
        case .pending: return .white.opacity(0.3)
        case .in_progress: return .neonOrange
        case .completed: return .neonBlue
        case .approved: return .neonGreen
        case .rejected: return .neonRed
        }
    }
}

struct QuickStat: View {
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
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .gameCard(glow: color.opacity(0.3))
    }
}

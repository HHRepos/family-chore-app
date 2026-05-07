import SwiftUI

struct QuestMapView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedChore: AssignedChore?
    @State private var showParticles = false
    @State private var showScreenTime = false
    @State private var showLeaderboard = false
    @State private var showAllChores = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header with XP
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text({ let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f.string(from: Date()) }())
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.3))
                                Text("Welcome back,")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text(auth.user?.firstName ?? "Hero")
                                    .font(.system(size: 24, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            // Points coin
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.neonYellow)
                                Text("\(shop.points)")
                                    .font(.system(size: 18, weight: .black, design: .rounded))
                                    .foregroundStyle(.neonYellow)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.neonYellow.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonYellow.opacity(0.3), lineWidth: 1))
                            .bounceIn(delay: 0.2, appeared: appeared)
                        }

                        XPBar(points: shop.points)

                        // Streak
                        if let stats = shop.stats, stats.streak > 0 {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundStyle(.neonOrange)
                                Text("\(stats.streak) day streak!")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.neonOrange)
                                Spacer()
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.gameCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .slideUp(delay: 0, appeared: appeared)

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
                        Button { showScreenTime = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tv.fill").font(.system(size: 14))
                                Text("Screen").font(.system(size: 12, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonBlue)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.neonBlue.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.neonBlue.opacity(0.3), lineWidth: 1))
                        }
                    }

                    // ☀️ MORNING ROUTINE
                    if !choreStore.morningHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("☀️").font(.system(size: 16))
                                Text("Morning Routine").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                                Spacer()
                                if choreStore.morningComplete {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.neonYellow)
                                        Text("Morning Star +5").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                    }
                                } else {
                                    Text("+1 pt each").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            ForEach(choreStore.morningHabits) { habit in
                                HabitRow(chore: habit) { selectedChore = habit }
                            }
                        }
                        .gameCard(glow: choreStore.morningComplete ? .neonYellow.opacity(0.4) : .neonBlue.opacity(0.2))
                    }

                    // 🏠 TODAY'S CHORES
                    HStack {
                        Text("🏠").font(.system(size: 16))
                        Text("Today's Quests").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        let mainDone = choreStore.mainChores.filter { $0.status == .completed || $0.status == .approved }.count
                        Text("\(mainDone)/\(choreStore.mainChores.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                        Button { showAllChores = true } label: {
                            Text("See All").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonBlue)
                        }
                    }

                    if choreStore.mainChores.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(.neonGreen.opacity(0.3))
                            Text("No quests today!").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                        }.frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else {
                        ForEach(choreStore.activeMainChores) { chore in
                            QuestCard(chore: chore) { selectedChore = chore }
                        }
                        let completedMain = choreStore.mainChores.filter { $0.status == .completed || $0.status == .approved }
                        if !completedMain.isEmpty {
                            Text("Completed").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(completedMain) { chore in
                                QuestCard(chore: chore) { selectedChore = chore }.opacity(0.5)
                            }
                        }
                    }

                    // 🌙 EVENING ROUTINE
                    if !choreStore.eveningHabits.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("🌙").font(.system(size: 16))
                                Text("Evening Routine").font(.system(size: 16, weight: .black, design: .rounded)).foregroundStyle(.white)
                                Spacer()
                                if choreStore.eveningComplete {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.neonYellow)
                                        Text("Evening Star +5").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                    }
                                } else {
                                    Text("+1 pt each").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                                }
                            }
                            ForEach(choreStore.eveningHabits) { habit in
                                HabitRow(chore: habit) { selectedChore = habit }
                            }
                        }
                        .gameCard(glow: choreStore.eveningComplete ? .neonYellow.opacity(0.4) : .neonPurple.opacity(0.2))
                    }

                    // Tips
                    if choreStore.activeMainChores.isEmpty && !choreStore.mainChores.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Tips", systemImage: "lightbulb.fill").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                            Text("Complete all morning habits for a Morning Star bonus (+5 pts)")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                            Text("Do all daily quests for a Weekly Superstar badge")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        }.gameCard(glow: .neonYellow.opacity(0.2))
                    }
                }
                .padding(16)
            }
            .refreshable {
                await loadData()
            }

            // Particle overlay
            if showParticles {
                ParticleExplosion()
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $selectedChore) { chore in
            QuestDetailView(chore: chore) {
                showParticles = true
                Task {
                    await loadData()
                    try? await Task.sleep(for: .seconds(1.2))
                    showParticles = false
                }
            }
        }
        .sheet(isPresented: $showScreenTime) { ScreenTimeView() }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView() }
        .sheet(isPresented: $showAllChores) { AllChoresView() }
        .task {
            await loadData()
            withAnimation { appeared = true }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await loadData() }
            }
        }
        .onChange(of: showLeaderboard) { _, isPresented in
            if !isPresented { Task { await loadData() } }
        }
        .onChange(of: showAllChores) { _, isPresented in
            if !isPresented { Task { await loadData() } }
        }
        .onChange(of: selectedChore?.assignedChoreId) { _, id in
            if id == nil { Task { await loadData() } }
        }
    }

    private func loadData() async {
        guard let userId = auth.userId, let familyId = auth.familyId else { return }
        await choreStore.loadUserChores(userId: userId)
        await shop.loadAll(userId: userId, familyId: familyId)
    }
}

// MARK: - Habit Row (compact, for morning/evening routines)
struct HabitRow: View {
    let chore: AssignedChore
    let onTap: () -> Void

    private var isDone: Bool { chore.status == .completed || chore.status == .approved }
    @State private var justCompleted = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isDone ? .neonGreen : .white.opacity(0.25))
                    .scaleEffect(justCompleted ? 1.3 : 1)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: justCompleted)

                Text(chore.choreName)
                    .font(.system(size: 14, weight: isDone ? .medium : .bold, design: .rounded))
                    .foregroundStyle(isDone ? .white.opacity(0.4) : .white)
                    .strikethrough(isDone, color: .white.opacity(0.2))

                Spacer()

                if !isDone {
                    Text("+\(chore.points)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.neonYellow.opacity(0.5))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

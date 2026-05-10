import SwiftUI

/// The Living Garden — kid's home screen.
///
/// Phase-1 implementation of the Living Garden redesign. Visuals are
/// placeholder (gradient sky, SwiftUI-rendered tree, emoji creatures)
/// until the illustrator delivers the watercolour + Ghibli asset pack
/// per the brief at `/designs/designer-brief.html`. Structure is final:
/// once illustrator hands over Lottie animations and SVGs, they swap
/// in here without changing the layout or the data wiring.
struct GardenView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragOffset: CGSize = .zero
    @State private var animatingCompletion: Bool = false
    @State private var bloomingFlowerId: String? = nil
    @State private var pointsBurst: Int? = nil
    @State private var lastPointsSeen: Int? = nil
    @State private var pollTask: Task<Void, Never>?

    /// Today's chores, ordered with active first then completed.
    private var todayCards: [AssignedChore] {
        let pending = choreStore.todaysChores.filter {
            $0.status == .pending || $0.status == .in_progress
        }
        let completed = choreStore.todaysChores.filter {
            $0.status == .completed || $0.status == .approved
        }
        return pending + completed
    }

    private var activeCards: [AssignedChore] {
        choreStore.todaysChores.filter { $0.status == .pending || $0.status == .in_progress }
    }

    private var topCard: AssignedChore? { activeCards.first }
    private var totalToday: Int { choreStore.todaysChores.count }
    private var completedToday: Int {
        choreStore.todaysChores.filter { $0.status == .completed || $0.status == .approved }.count
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                skyGradient.ignoresSafeArea()
                dappledLight.ignoresSafeArea().allowsHitTesting(false)

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    gardenStage(in: geo)
                    Spacer(minLength: 0)
                    cardStack(in: geo)
                }

                if let burst = pointsBurst {
                    burstOverlay(burst)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .task {
            await loadData()
            startPolling()
        }
        .onDisappear { stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await loadData() }
                startPolling()
            } else {
                stopPolling()
            }
        }
        .onChange(of: shop.points) { oldValue, newValue in
            handlePointsChange(from: oldValue, to: newValue)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(auth.user?.firstName ?? "Hero")'s garden")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.gardenInk)
                Text("Day \(daysCount) · \(scenicSubtitle)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.gardenInkSoft)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(Color.gardenSeed)
                Text("\(shop.points)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.gardenSeed)
                    .contentTransition(.numericText(value: Double(shop.points)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    // MARK: - Garden stage

    @ViewBuilder
    private func gardenStage(in geo: GeometryProxy) -> some View {
        ZStack {
            // Tree
            tree
                .frame(width: 220, height: 240)
                .offset(y: -8)
                .modifier(SwaySway())

            // Past flowers — small, dim, scattered around the tree's base.
            // Pure decoration — not interactive, doesn't represent today.
            ForEach(Array(historicalFlowers().prefix(8).enumerated()), id: \.offset) { idx, hf in
                Text(hf.emoji)
                    .font(.system(size: 12))
                    .opacity(0.4)
                    .position(x: hf.x * geo.size.width, y: 350 + hf.y * 50)
                    .allowsHitTesting(false)
            }

            // Wandering cat — once per family with a real pet config.
            // Drifts left-to-right, no flip.
            if hasRealPet {
                Text(petEmoji)
                    .font(.system(size: 28))
                    .modifier(WanderRight(width: geo.size.width))
                    .position(x: 0, y: geo.size.height * 0.6 + 20)
                    .allowsHitTesting(false)
            }

            // Today's progress shows above the card stack as a simple
            // text-only indicator instead of floating flower bubbles.
            VStack(spacing: 4) {
                Spacer()
                if !todayCards.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(0..<min(totalToday, 8), id: \.self) { idx in
                            Circle()
                                .fill(idx < completedToday ? Color.gardenAccentGreen : Color.white.opacity(0.55))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text("\(completedToday) of \(totalToday) watered today")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.gardenInkSoft)
                }
            }
            .padding(.bottom, 180)

            // Empty state if no chores at all today
            if todayCards.isEmpty && !choreStore.isLoading {
                VStack(spacing: 6) {
                    Text("That's all today.")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.gardenInk)
                    Text("Well done.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.gardenInkSoft)
                }
                .padding(.top, 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tree — placeholder built from overlapping Circles. Real illustrator
    /// art lands as `Image("tree-day1")` etc with multiple growth stages.
    private var tree: some View {
        ZStack {
            // Trunk
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [Color(red: 0.43, green: 0.30, blue: 0.18), Color(red: 0.55, green: 0.40, blue: 0.25)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(width: 18, height: 100)
                .offset(y: 80)

            // Foliage layers — slightly different greens, overlapping ellipses
            Group {
                Ellipse()
                    .fill(Color(red: 0.50, green: 0.65, blue: 0.30))
                    .frame(width: 180, height: 110)
                    .offset(y: -30)
                Ellipse()
                    .fill(Color(red: 0.58, green: 0.74, blue: 0.37))
                    .frame(width: 140, height: 90)
                    .offset(x: -40, y: 0)
                Ellipse()
                    .fill(Color(red: 0.58, green: 0.74, blue: 0.37))
                    .frame(width: 140, height: 90)
                    .offset(x: 40, y: 0)
                Ellipse()
                    .fill(Color(red: 0.66, green: 0.81, blue: 0.45))
                    .frame(width: 200, height: 90)
                    .offset(y: 30)
            }
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 6)
        }
    }

    // MARK: - Card stack

    @ViewBuilder
    private func cardStack(in geo: GeometryProxy) -> some View {
        if let active = topCard {
            ZStack {
                // Bottom shadow stack to suggest depth
                if activeCards.count >= 3 {
                    cardShape
                        .fill(Color(red: 0.92, green: 0.90, blue: 0.85))
                        .opacity(0.5)
                        .scaleEffect(0.88)
                        .offset(y: 18)
                }
                if activeCards.count >= 2 {
                    cardShape
                        .fill(Color(red: 0.96, green: 0.94, blue: 0.88))
                        .opacity(0.85)
                        .scaleEffect(0.94)
                        .offset(y: 9)
                }

                // Front card
                ChoreCardFront(chore: active, totalActive: activeCards.count, completedToday: completedToday, totalToday: totalToday)
                    .offset(y: dragOffset.height)
                    .opacity(animatingCompletion ? 0 : 1)
                    .scaleEffect(animatingCompletion ? 0.85 : 1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !animatingCompletion {
                                    dragOffset = CGSize(width: 0, height: min(0, value.translation.height))
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -80 && !animatingCompletion {
                                    completeTopCard()
                                } else {
                                    withAnimation(.spring(response: 0.3)) { dragOffset = .zero }
                                }
                            }
                    )
                    .onTapGesture { /* placeholder — long-press to spread */ }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    private var cardShape: some Shape { RoundedRectangle(cornerRadius: 18) }

    // MARK: - Burst overlay (+N points)

    @ViewBuilder
    private func burstOverlay(_ delta: Int) -> some View {
        VStack {
            HStack {
                Spacer()
                Text("+\(delta)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.gardenSeed)
                    .shadow(color: Color.gardenSeed.opacity(0.6), radius: 14)
                    .padding(.trailing, 32).padding(.top, 30)
            }
            Spacer()
        }
    }

    // MARK: - Actions

    private func completeTopCard() {
        guard let card = topCard else { return }
        let bloomingId = card.assignedChoreId
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // animate card flying up and fading
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: 0, height: -260)
            animatingCompletion = true
            bloomingFlowerId = bloomingId
        }
        Task {
            await choreStore.completeChore(card)
            // refresh data so the next card and points come in
            await loadData()
            try? await Task.sleep(for: .seconds(0.3))
            await MainActor.run {
                dragOffset = .zero
                animatingCompletion = false
                bloomingFlowerId = nil
            }
        }
    }

    private func loadData() async {
        guard let userId = auth.userId, let familyId = auth.familyId else { return }
        await choreStore.loadUserChores(userId: userId)
        await shop.loadAll(userId: userId, familyId: familyId)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { return }
                await loadData()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func handlePointsChange(from oldValue: Int, to newValue: Int) {
        if lastPointsSeen == nil { lastPointsSeen = newValue; return }
        guard newValue > oldValue else { lastPointsSeen = newValue; return }
        let delta = newValue - oldValue
        lastPointsSeen = newValue
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            pointsBurst = delta
        }
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeOut(duration: 0.4)) { pointsBurst = nil }
        }
    }

    // MARK: - Visuals

    private var skyGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:  // dawn
            return LinearGradient(
                colors: [Color(red: 0.99, green: 0.91, blue: 0.77), Color(red: 0.96, green: 0.81, blue: 0.62)],
                startPoint: .top, endPoint: .bottom)
        case 8..<17: // day
            return LinearGradient(
                colors: [Color(red: 0.91, green: 0.95, blue: 0.84), Color(red: 0.76, green: 0.83, blue: 0.63)],
                startPoint: .top, endPoint: .bottom)
        case 17..<20: // dusk
            return LinearGradient(
                colors: [Color(red: 0.97, green: 0.75, blue: 0.63), Color(red: 0.58, green: 0.38, blue: 0.56)],
                startPoint: .top, endPoint: .bottom)
        default: // night
            return LinearGradient(
                colors: [Color(red: 0.16, green: 0.21, blue: 0.36), Color(red: 0.08, green: 0.10, blue: 0.20)],
                startPoint: .top, endPoint: .bottom)
        }
    }

    /// Warm overlay suggesting filtered sunlight through the canopy.
    private var dappledLight: some View {
        RadialGradient(
            colors: [Color(red: 1, green: 0.94, blue: 0.78).opacity(0.18), .clear],
            center: .top, startRadius: 60, endRadius: 280
        )
    }

    private var scenicSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:   return "soft dawn breeze"
        case 8..<17:  return "warm sunshine"
        case 17..<20: return "amber dusk"
        default:      return "starlit garden"
        }
    }

    private var daysCount: Int {
        // Placeholder until backend exposes garden_started_at — count from
        // the user's earliest assigned_chores due_date. For now, derive from
        // shop.stats.totalCompleted divided by ~3 chores/day, capped sensibly.
        let total = shop.stats?.totalCompleted ?? 0
        return max(1, total / 3 + 1)
    }

    private var hasRealPet: Bool { /* will read from family.houseDetails.pets later */ true }
    private var petEmoji: String { "🐱" }

    // Position lookup for today's flowers around the tree
    private func flowerPosition(for index: Int, total: Int, in geo: GeometryProxy) -> CGPoint {
        // Spread flowers in two arcs — top arc and bottom arc — around the tree centre
        let centerX = geo.size.width / 2
        let centerY: CGFloat = 220
        let positions: [CGPoint] = [
            CGPoint(x: centerX - 100, y: centerY - 30),
            CGPoint(x: centerX + 100, y: centerY - 30),
            CGPoint(x: centerX - 60, y: centerY + 60),
            CGPoint(x: centerX + 60, y: centerY + 60),
            CGPoint(x: centerX, y: centerY + 100)
        ]
        return positions[min(index, positions.count - 1)]
    }

    /// Past flowers as background population — random-feeling but stable.
    private struct HistoricalFlower {
        let emoji: String
        let x: CGFloat   // 0..1
        let y: CGFloat   // 0..1
    }
    private func historicalFlowers() -> [HistoricalFlower] {
        // Build a fixed set seeded by user id so they're stable across launches
        let pool = ["🪥", "🍽️", "🚿", "🧺", "🐱", "📚"]
        var out: [HistoricalFlower] = []
        let count = min(20, (shop.stats?.totalCompleted ?? 0))
        let seed = (auth.userId?.hashValue ?? 0) & 0xFFFF
        for i in 0..<count {
            let e = pool[(seed + i) % pool.count]
            let x = CGFloat((seed + i * 17) % 100) / 100.0
            let y = CGFloat((seed + i * 23) % 100) / 100.0
            out.append(HistoricalFlower(emoji: e, x: 0.05 + x * 0.9, y: 0.15 + y * 0.7))
        }
        return out
    }
}

// MARK: - Card front content

private struct ChoreCardFront: View {
    let chore: AssignedChore
    let totalActive: Int
    let completedToday: Int
    let totalToday: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(categoryLabel)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(categoryColor)
                Spacer()
                Text("\(completedToday) / \(totalToday)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.gardenInkSoft)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(chore.choreEmoji)
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 1) {
                    Text(chore.choreName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.gardenInk)
                        .lineLimit(2)
                    Text(chore.subtitleText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.gardenInkSoft)
                }
                Spacer()
            }
            Text("⌃ swipe up to water")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.gardenInkSoft.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(height: 110)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: -4)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: -2)
    }

    private var categoryLabel: String {
        switch chore.choreType {
        case "daily_habit": return "DAILY HABIT"
        case "routine":     return "ROUTINE"
        case "personal_space": return "YOUR ROOM"
        case "laundry":     return "LAUNDRY"
        default:            return "TODAY"
        }
    }
    private var categoryColor: Color {
        switch chore.choreType {
        case "daily_habit": return .gardenAccentWarm
        case "routine":     return .gardenAccentGreen
        default:            return .gardenInkSoft
        }
    }
}

// MARK: - Flower bubble with bloom animation

private struct FlowerBubble: View {
    let emoji: String
    let isBloomed: Bool
    let isAnimating: Bool

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if isBloomed {
                Circle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(isAnimating ? 1.4 : 1.0)
                    .opacity(isAnimating ? 0 : 0.6)
            }
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1.5))
                Text(emoji)
                    .font(.system(size: 22))
            }
            .opacity(isBloomed ? 1 : 0.55)
            .scaleEffect(isAnimating ? 1.25 : 1.0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.55), value: isAnimating)
    }
}

// MARK: - Animations

/// Gentle 1° sway in the wind, applied to the tree.
private struct SwaySway: ViewModifier {
    @State private var phase: Double = 0
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(sin(phase) * 1.1), anchor: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    phase = .pi
                }
            }
    }
}

/// Drifts a creature from off-screen-left to off-screen-right, fading at edges.
/// No flip — direction stays consistent the whole way across.
private struct WanderRight: ViewModifier {
    let width: CGFloat
    @State private var x: CGFloat = -60
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .opacity(opacity)
            .onAppear {
                withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
                    x = width + 80
                }
                withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: false)) {
                    opacity = 1
                }
                Task {
                    // Fade-in then full-on then fade-out cycle
                    try? await Task.sleep(for: .seconds(15))
                    withAnimation { opacity = 0 }
                }
            }
    }
}

// MARK: - Color tokens

private extension Color {
    static let gardenInk         = Color(red: 0.17, green: 0.23, blue: 0.14)
    static let gardenInkSoft     = Color(red: 0.30, green: 0.37, blue: 0.18)
    static let gardenSeed        = Color(red: 0.42, green: 0.31, blue: 0.10)
    static let gardenAccentWarm  = Color(red: 0.72, green: 0.46, blue: 0.12)
    static let gardenAccentGreen = Color(red: 0.37, green: 0.54, blue: 0.15)
}

// MARK: - AssignedChore helpers (UI-only, no impact on existing model)

private extension AssignedChore {
    /// Map chore name + category to a fitting emoji for a flower glyph.
    /// Will be replaced by category-coloured illustrated flowers when the
    /// asset pack lands.
    var choreEmoji: String {
        let name = choreName.lowercased()
        if name.contains("teeth") { return "🪥" }
        if name.contains("brush") { return "🪥" }
        if name.contains("plate") { return "🍽️" }
        if name.contains("dish") { return "🍽️" }
        if name.contains("shower") { return "🚿" }
        if name.contains("bath") { return "🚿" }
        if name.contains("bed") { return "🛏️" }
        if name.contains("tidy") { return "🧺" }
        if name.contains("room") { return "🧺" }
        if name.contains("laundry") { return "👕" }
        if name.contains("clothes") { return "👕" }
        if name.contains("walk") { return "🐕" }
        if name.contains("feed") { return "🍲" }
        if name.contains("litter") { return "🧹" }
        if name.contains("vacuum") { return "🧹" }
        if name.contains("trash") { return "🗑️" }
        if name.contains("bin") { return "🗑️" }
        if choreType == "daily_habit" { return "🌼" }
        if choreType == "routine" { return "🐾" }
        return "🌷"
    }

    var subtitleText: String {
        switch choreType {
        case "daily_habit":
            return "Today's morning flower"
        case "routine":
            return "Today's pet care"
        case "personal_space":
            return "Your own space"
        default:
            return "Today's flower"
        }
    }
}

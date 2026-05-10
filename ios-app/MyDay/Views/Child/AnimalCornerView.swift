import SwiftUI

/// 🐾 Animal Corner — kid's view of real-world pet care.
///
/// Phase 1: shows each pet from `family.houseDetails.pets` with the
/// pet care chores filtered for this kid. Same swipe-to-water gesture
/// as the Garden home applies — these chores ARE garden flowers, just
/// rendered in their natural habitat (the meadow alongside the pet)
/// instead of around the tree.
struct AnimalCornerView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(FamilyStore.self) private var familyStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase

    @State private var dragOffset: CGSize = .zero
    @State private var animatingCompletion = false
    @State private var pollTask: Task<Void, Never>?

    /// Pet-related chores assigned to this kid for today.
    private var myPetChores: [AssignedChore] {
        choreStore.todaysChores.filter {
            $0.userId == auth.userId &&
            ($0.choreType == "routine" || $0.choreName.lowercased().contains("fifi") ||
             $0.choreName.lowercased().contains("walk") || $0.choreName.lowercased().contains("feed") ||
             $0.choreName.lowercased().contains("litter"))
        }
    }

    private var activePetChores: [AssignedChore] {
        myPetChores.filter { $0.status == .pending || $0.status == .in_progress }
    }

    private var topCard: AssignedChore? { activePetChores.first }

    private var pets: [Pet] {
        familyStore.family?.houseDetails?.pets ?? []
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                meadowGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    Spacer(minLength: 0)
                    meadowScene(in: geo)
                    Spacer(minLength: 0)
                    if topCard != nil {
                        cardStack(in: geo)
                    } else {
                        nothingTodoFooter
                    }
                }
            }
        }
        .task {
            await loadData()
            startPolling()
        }
        .onDisappear { stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await loadData() }; startPolling() }
            else { stopPolling() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Animal corner")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.gardenInk)
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.gardenInkSoft)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").foregroundStyle(Color.gardenSeed)
                Text("\(shop.points)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.gardenSeed)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func meadowScene(in geo: GeometryProxy) -> some View {
        ZStack {
            grassMound
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .offset(y: 60)

            VStack(spacing: 14) {
                if pets.isEmpty {
                    emptyPetsState
                } else {
                    ForEach(pets) { pet in
                        petCard(pet)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
        }
    }

    private var grassMound: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Color(red: 0.76, green: 0.86, blue: 0.55),
                         Color(red: 0.56, green: 0.69, blue: 0.35)],
                startPoint: .top, endPoint: .bottom))
            .opacity(0.55)
            .scaleEffect(x: 1.4)
    }

    @ViewBuilder
    private func petCard(_ pet: Pet) -> some View {
        let petChores = myPetChores.filter { chore in
            chore.choreName.lowercased().contains(pet.name.lowercased())
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(petEmoji(for: pet.type))
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pet.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Color.gardenInk)
                    Text(petLabel(for: pet))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.gardenInkSoft)
                }
                Spacer()
                if !petChores.isEmpty {
                    let activeCount = petChores.filter { $0.status == .pending || $0.status == .in_progress }.count
                    if activeCount > 0 {
                        Text("\(activeCount) to do")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.72, green: 0.36, blue: 0.13))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(red: 1.0, green: 0.93, blue: 0.78))
                            .clipShape(Capsule())
                    } else {
                        Text("All done")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.27, green: 0.51, blue: 0.18))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color(red: 0.85, green: 0.93, blue: 0.72))
                            .clipShape(Capsule())
                    }
                }
            }

            // Per-pet chore mini list
            if !petChores.isEmpty {
                VStack(spacing: 6) {
                    ForEach(petChores) { chore in
                        HStack(spacing: 10) {
                            Image(systemName: chore.status == .approved || chore.status == .completed
                                  ? "checkmark.circle.fill"
                                  : "circle")
                                .foregroundStyle(chore.status == .approved || chore.status == .completed
                                                 ? Color.gardenAccentGreen
                                                 : Color.gardenInkSoft.opacity(0.4))
                                .font(.system(size: 16))
                            Text(chore.choreName)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.gardenInk)
                                .strikethrough(chore.status == .approved || chore.status == .completed)
                            Spacer()
                            Text("+\(chore.points) 🌱")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.gardenSeed.opacity(0.6))
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    @ViewBuilder
    private var emptyPetsState: some View {
        VStack(spacing: 8) {
            Text("🐾")
                .font(.system(size: 56))
            Text("No pets in your garden yet")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.gardenInk)
            Text("Ask a parent to add a pet from the Codex.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.gardenInkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func cardStack(in geo: GeometryProxy) -> some View {
        if let active = topCard {
            ZStack {
                if activePetChores.count >= 2 {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 0.96, green: 0.94, blue: 0.88))
                        .opacity(0.85)
                        .scaleEffect(0.94)
                        .offset(y: 9)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PET CARE · 1 of \(activePetChores.count)")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(Color.gardenAccentGreen)
                        Spacer()
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Text(active.choreEmoji)
                            .font(.system(size: 32))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(active.choreName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.gardenInk)
                            Text("Earns \(active.points) seeds")
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
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)
        }
    }

    private var nothingTodoFooter: some View {
        VStack(spacing: 4) {
            Text(pets.isEmpty ? "Add a pet to start" : "All caught up — well looked after.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.gardenInkSoft)
        }
        .padding(.bottom, 30)
    }

    // MARK: - Helpers

    private var headerSubtitle: String {
        let active = activePetChores.count
        if pets.isEmpty { return "no pets in the family yet" }
        if active == 0 { return "everyone fed and happy" }
        return "\(active) to do · \(pets.count) pet\(pets.count > 1 ? "s" : "")"
    }

    private var meadowGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.96, blue: 0.86),
                     Color(red: 0.94, green: 0.89, blue: 0.72)],
            startPoint: .top, endPoint: .bottom)
    }

    private func petEmoji(for type: String) -> String {
        switch type.lowercased() {
        case "dog": return "🐕"
        case "cat": return "🐱"
        case "bird", "parrot": return "🦜"
        case "fish": return "🐠"
        case "rabbit", "bunny": return "🐰"
        case "hamster": return "🐹"
        default: return "🐾"
        }
    }

    private func petLabel(for pet: Pet) -> String {
        let care = (pet.walkRotationChildren ?? []).count + (pet.litterRotationChildren ?? []).count
        if care == 0 { return "Cared for by everyone" }
        return "\(pet.type.capitalized) · in your rotation"
    }

    private func completeTopCard() {
        guard let card = topCard else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            dragOffset = CGSize(width: 0, height: -260)
            animatingCompletion = true
        }
        Task {
            await choreStore.completeChore(card)
            await loadData()
            try? await Task.sleep(for: .seconds(0.3))
            await MainActor.run {
                dragOffset = .zero
                animatingCompletion = false
            }
        }
    }

    private func loadData() async {
        guard let userId = auth.userId, let familyId = auth.familyId else { return }
        await choreStore.loadUserChores(userId: userId)
        await familyStore.load(familyId: familyId)
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
}

private extension Color {
    static let gardenInk         = Color(red: 0.17, green: 0.23, blue: 0.14)
    static let gardenInkSoft     = Color(red: 0.30, green: 0.37, blue: 0.18)
    static let gardenSeed        = Color(red: 0.42, green: 0.31, blue: 0.10)
    static let gardenAccentGreen = Color(red: 0.37, green: 0.54, blue: 0.15)
}

private extension AssignedChore {
    var choreEmoji: String {
        let n = choreName.lowercased()
        if n.contains("walk") { return "🐕" }
        if n.contains("feed") { return "🍲" }
        if n.contains("litter") { return "🧹" }
        if n.contains("brush") { return "🪥" }
        if n.contains("water") { return "💧" }
        return "🐾"
    }
}

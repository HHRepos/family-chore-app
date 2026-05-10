import SwiftUI

/// 🏡 Family Park — parent's home view.
///
/// Replaces the old CommandCenterView. One row per family member with a
/// mini tree, today's progress bar, and a ripe-count badge if there's
/// anything to approve. Approvals queue lives as a single black ribbon
/// at the top — tap to drill into the unapproved-chores sheet.
struct FamilyParkView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase

    @State private var showApprovals = false
    @State private var showManageFamily = false
    @State private var pollTask: Task<Void, Never>?

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private var pendingCount: Int { choreStore.pendingApprovals.count }

    private var membersInRotation: [FamilyMember] {
        let kids = familyStore.children
        let participatingParents = familyStore.members.filter { $0.role == "parent" && ($0.participates == true) }
        return kids + participatingParents
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    if pendingCount > 0 {
                        approvalRibbon
                    }
                    if membersInRotation.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 12) {
                            ForEach(membersInRotation) { member in
                                plotCard(for: member)
                            }
                        }
                    }
                    quickActions
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 32)
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
        .sheet(isPresented: $showApprovals) {
            ApprovalsView()
        }
        .sheet(isPresented: $showManageFamily) {
            ManageFamilyView()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Family park")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.parkInk)
                Text("\(familyStore.family?.familyName ?? "Your family") · \(formattedDate)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.parkInkSoft)
            }
            Spacer()
            // Avatar
            AvatarView(
                seed: auth.userId ?? "parent",
                size: 48,
                customizations: auth.user?.avatarCustomizations ?? [],
                fallbackInitial: auth.user?.firstName
            )
        }
    }

    private var approvalRibbon: some View {
        Button { showApprovals = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.23))
                        .frame(width: 32, height: 32)
                    Text("\(pendingCount)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(pendingCount) ripe to harvest")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tap to review and approve")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
            .background(Color(red: 0.17, green: 0.23, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func plotCard(for member: FamilyMember) -> some View {
        let memberChores = choreStore.chores.filter { $0.userId == member.userId && String($0.dueDate.prefix(10)) == todayString }
        let total = memberChores.count
        let done = memberChores.filter { $0.status == .approved || $0.status == .completed }.count
        let ripe = memberChores.filter { $0.status == .completed }.count
        let progress = total > 0 ? Double(done) / Double(total) : 0

        HStack(spacing: 14) {
            miniTree(progress: progress)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName(member))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.parkInk)
                    if member.role == "parent" {
                        Text("you")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.parkInkSoft.opacity(0.15))
                            .foregroundStyle(Color.parkInkSoft)
                            .clipShape(Capsule())
                    }
                }
                Text(progressText(done: done, total: total))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.parkInkSoft)
                ProgressView(value: progress)
                    .tint(Color(red: 0.49, green: 0.65, blue: 0.31))
                    .frame(maxWidth: 160)
            }
            Spacer()
            if ripe > 0 {
                Text("\(ripe) ripe")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(red: 1.0, green: 0.36, blue: 0.23))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(.white.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            Button { showManageFamily = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Color.parkAccent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Manage family")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.parkInk)
                        Text("Add or edit kids · invite codes · pets")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.parkInkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.parkInkSoft.opacity(0.4))
                }
                .padding(14)
                .background(.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("🌱")
                .font(.system(size: 48))
            Text("No gardens yet")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.parkInk)
            Text("Add your kids from Manage family.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.parkInkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Mini tree

    @ViewBuilder
    private func miniTree(progress: Double) -> some View {
        ZStack {
            // Trunk
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(red: 0.43, green: 0.30, blue: 0.18))
                .frame(width: 6, height: 28)
                .offset(y: 16)
            // Foliage layers — fewer for early days, more as progress fills
            let foliageOpacity = 0.55 + 0.45 * progress
            Ellipse()
                .fill(Color(red: 0.50, green: 0.65, blue: 0.30).opacity(foliageOpacity))
                .frame(width: 56, height: 38)
                .offset(y: -4)
            Ellipse()
                .fill(Color(red: 0.66, green: 0.81, blue: 0.45).opacity(foliageOpacity))
                .frame(width: 38, height: 26)
                .offset(y: 4)
        }
    }

    // MARK: - Helpers

    private func displayName(_ m: FamilyMember) -> String {
        let me = m.userId == auth.userId
        return me ? "\(m.firstName) (you)" : m.firstName
    }

    private func progressText(done: Int, total: Int) -> String {
        if total == 0 { return "no flowers today" }
        if done == total { return "all watered ✓" }
        return "\(done) of \(total) watered today"
    }

    private var formattedDate: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f.string(from: Date())
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.96, green: 0.92, blue: 0.82),
                     Color(red: 0.90, green: 0.85, blue: 0.66)],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - Lifecycle

    private func loadData() async {
        guard let familyId = auth.familyId, let userId = auth.userId else { return }
        await familyStore.load(familyId: familyId)
        await choreStore.loadFamilyChores(familyId: familyId)
        await choreStore.loadApprovals(familyId: familyId)
        await shop.loadAll(userId: userId, familyId: familyId)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
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
    static let parkInk     = Color(red: 0.18, green: 0.23, blue: 0.13)
    static let parkInkSoft = Color(red: 0.43, green: 0.36, blue: 0.16)
    static let parkAccent  = Color(red: 0.49, green: 0.65, blue: 0.31)
}

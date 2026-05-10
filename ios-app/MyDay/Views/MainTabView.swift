import SwiftUI

struct MainTabView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(ChoreStore.self) private var choreStore

    @State private var childTab: ChildTab = .quests
    @State private var parentTab: ParentTab = .command

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Content
                Group {
                    if auth.isChild {
                        childContent
                    } else {
                        parentContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Tab bar
                if auth.isChild {
                    GameTabBarView(
                        selected: $childTab,
                        icon: { $0.icon },
                        label: { $0.label }
                    )
                } else {
                    GameTabBarView(
                        selected: $parentTab,
                        icon: { $0.icon },
                        label: { $0.label },
                        badgeCount: { tab in
                            tab == .approvals ? choreStore.pendingApprovals.count : 0
                        }
                    )
                }
            }
        }
        .task {
            if let familyId = auth.familyId {
                await familyStore.load(familyId: familyId)
                if auth.isParent {
                    await choreStore.loadFamilyChores(familyId: familyId)
                    await choreStore.loadApprovals(familyId: familyId)
                }
            }
        }
    }

    @ViewBuilder
    private var childContent: some View {
        // Living Garden zones — Build 16 onwards.
        // Tab enum case names retained for routing; views remapped.
        switch childTab {
        case .quests: GardenView()         // 🏡 Home garden
        case .shop: ShopView()             // 🌿 Wildlife glade (rebrand of shop in Phase 2)
        case .contracts: AnimalCornerView() // 🐾 Animal corner (real pets)
        case .rules: FountainView()        // ⛲ By the fountain (play time)
        case .profile: ProfileView()       // 👤 Profile
        }
    }

    @ViewBuilder
    private var parentContent: some View {
        // Living Garden parent zones.
        switch parentTab {
        case .command: FamilyParkView()    // 🏡 Family park
        case .approvals: PetConfigView()   // 🐾 Pets — manage pet config + rotation
        case .contracts: FountainView()    // ⛲ Fountain — same view as kids; parent sees defaults
        case .shop: ParentShopView()       // 🌿 Glade
        case .settings: ParentSettingsView() // 📖 Codex (rebranded label)
        }
    }
}

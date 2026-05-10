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
        switch childTab {
        case .quests: GardenView()       // Living Garden — Build 15 onwards
        case .shop: ShopView()
        case .contracts: ContractBoardView()
        case .rules: FamilyRulesView()
        case .profile: ProfileView()
        }
    }

    @ViewBuilder
    private var parentContent: some View {
        switch parentTab {
        case .command: CommandCenterView()
        case .approvals: ApprovalsView()
        case .contracts: ContractBoardView()
        case .shop: ParentShopView()
        case .settings: ParentSettingsView()
        }
    }
}

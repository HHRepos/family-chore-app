import SwiftUI

enum ChildTab: String, CaseIterable {
    case quests, shop, contracts, rules, profile

    var icon: String {
        switch self {
        case .quests: return "scroll.fill"
        case .shop: return "storefront.fill"
        case .contracts: return "target"
        case .rules: return "calendar"
        case .profile: return "person.fill"
        }
    }

    var label: String {
        switch self {
        case .quests: return "Quests"
        case .shop: return "Shop"
        case .contracts: return "Contracts"
        case .rules: return "Schedule"
        case .profile: return "Profile"
        }
    }
}

enum ParentTab: String, CaseIterable {
    case command, approvals, contracts, shop, settings

    var icon: String {
        switch self {
        case .command: return "square.grid.2x2.fill"
        case .approvals: return "checkmark.seal.fill"
        case .contracts: return "target"
        case .shop: return "storefront.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .command: return "HQ"
        case .approvals: return "Approve"
        case .contracts: return "Contracts"
        case .shop: return "Shop"
        case .settings: return "Settings"
        }
    }
}

struct GameTabBarView<Tab: Hashable & CaseIterable & RawRepresentable>: View where Tab.RawValue == String, Tab.AllCases: RandomAccessCollection {
    @Binding var selected: Tab
    let icon: (Tab) -> String
    let label: (Tab) -> String
    var badgeCount: ((Tab) -> Int)? = nil

    var body: some View {
        HStack {
            ForEach(Array(Tab.allCases), id: \.rawValue) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) { selected = tab }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: icon(tab))
                                .font(.system(size: 20))
                                .symbolEffect(.bounce, value: selected == tab)

                            if let count = badgeCount?(tab), count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(.white)
                                    .padding(3)
                                    .background(.neonRed)
                                    .clipShape(Circle())
                                    .offset(x: 8, y: -4)
                            }
                        }

                        Text(label(tab))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selected == tab ? .neonBlue : .white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color.gameCard)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.neonBlue.opacity(0.1)).frame(height: 1)
        }
    }
}

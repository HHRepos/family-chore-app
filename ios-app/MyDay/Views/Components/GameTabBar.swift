import SwiftUI

enum ChildTab: String, CaseIterable {
    /// Living Garden zone names. Case names retained for routing
    /// compatibility, but labels and icons reflect the new design:
    /// 🏡 Home · 🐾 Animals · 🌿 Glade · ⛲ Fountain · 👤 Profile
    case quests, shop, contracts, rules, profile

    var icon: String {
        switch self {
        case .quests: return "leaf.fill"            // Home garden
        case .shop: return "sparkles"               // Wildlife glade (decoration shop)
        case .contracts: return "pawprint.fill"     // Animal corner (real pets)
        case .rules: return "drop.fill"             // By the fountain (play time)
        case .profile: return "person.fill"
        }
    }

    var label: String {
        switch self {
        case .quests: return "Garden"
        case .shop: return "Glade"
        case .contracts: return "Animals"
        case .rules: return "Fountain"
        case .profile: return "Profile"
        }
    }
}

enum ParentTab: String, CaseIterable {
    /// Living Garden parent zones. Case names retained for routing
    /// compatibility:
    /// 🏡 Park · 🐾 Pets · 🌿 Glade · ⛲ Fountain · 📖 Codex
    case command, approvals, contracts, shop, settings

    var icon: String {
        switch self {
        case .command: return "tree.fill"           // Family park
        case .approvals: return "pawprint.fill"     // Pet management
        case .contracts: return "drop.fill"         // Fountain (play settings)
        case .shop: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .command: return "Park"
        case .approvals: return "Pets"
        case .contracts: return "Fountain"
        case .shop: return "Glade"
        case .settings: return "Codex"
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

import SwiftUI

struct FamilyRulesView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @State private var details: HouseDetails?

    private var members: [FamilyMember] { familyStore.family?.members ?? [] }
    private let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    private var todayDay: String {
        let d = Calendar.current.component(.weekday, from: Date())
        return weekdays[d == 1 ? 6 : d - 2]
    }

    private func memberName(_ id: String) -> String {
        members.first(where: { $0.userId == id })?.firstName ?? "?"
    }

    private func rotationChild(_ children: [String], weekly: Bool = false) -> String? {
        guard !children.isEmpty else { return nil }
        if weekly {
            let week = Calendar.current.component(.weekOfYear, from: Date())
            return children[week % children.count]
        }
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return children[day % children.count]
    }

    /// Check if a rotation child ID is the current user (for highlighting "my turn")
    private func isMyTurn(_ childId: String?) -> Bool {
        guard let childId, auth.isChild else { return false }
        return childId == auth.userId
    }

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed.fill").font(.system(size: 40)).foregroundStyle(.neonBlue).neonGlow(.neonBlue, radius: 12)
                        Text("Family Rules").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                        if auth.isChild {
                            Text("Here's what's happening today")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }.padding(.top, 12)

                    if let d = details {
                        // Today's Summary (child-focused)
                        if auth.isChild {
                            todaySummary(d)
                        }

                        // Rooms — parent view only. Kids don't need the
                        // house-wide asset list.
                        if auth.isParent, let rooms = d.scannedRooms, !rooms.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Scanned Rooms", systemImage: "house.fill").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonBlue)
                                ForEach(rooms, id: \.name) { room in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(room.name).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                            Spacer()
                                            Text("\(room.assets.count) items").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                                        }
                                        if !room.assets.isEmpty {
                                            let shown = room.assets.prefix(6)
                                            let extra = room.assets.count - shown.count
                                            HStack(spacing: 4) {
                                                ForEach(Array(shown), id: \.self) { asset in
                                                    Text(asset).font(.system(size: 9, weight: .medium, design: .rounded))
                                                        .foregroundStyle(.neonBlue).padding(.horizontal, 6).padding(.vertical, 2)
                                                        .background(Color.neonBlue.opacity(0.1)).clipShape(Capsule())
                                                }
                                                if extra > 0 {
                                                    Text("+\(extra)").font(.system(size: 9, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white.opacity(0.3))
                                                }
                                            }
                                        }
                                    }
                                    .padding(10).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }.gameCard(glow: .neonBlue.opacity(0.3))
                        }

                        // Bins — parents see everything; kids only see if they're in
                        // the rotation OR if the rotation is empty (so the family
                        // hasn't decided yet).
                        if let bin = d.binSchedule, !bin.collectionDays.isEmpty {
                            let myId = auth.userId ?? ""
                            let kidVisible = bin.rotationChildren.isEmpty || bin.rotationChildren.contains(myId)
                            if auth.isParent || kidVisible {
                                binSection(bin)
                            }
                        }

                        // Pets — parents see all, kids see only pets they're rotated in.
                        if let pets = d.pets, !pets.isEmpty {
                            let myId = auth.userId ?? ""
                            let visible = auth.isChild
                                ? pets.filter { p in
                                    (p.walkRotationChildren?.contains(myId) ?? false) ||
                                    (p.litterRotationChildren?.contains(myId) ?? false) ||
                                    // No rotation set up at all → still show so the
                                    // child knows the pet exists and which chores
                                    // their family hasn't assigned yet.
                                    (p.walkRotationChildren?.isEmpty ?? true) &&
                                    (p.litterRotationChildren?.isEmpty ?? true)
                                }
                                : pets
                            if !visible.isEmpty { petSection(visible) }
                        }

                        // Gaming — children see only their own, parents see all
                        if let gaming = d.gamingSchedule, !gaming.isEmpty {
                            gamingSection(gaming)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "book.closed").font(.system(size: 40)).foregroundStyle(.white.opacity(0.15))
                            Text("No rules set up yet").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            if auth.isChild {
                                Text("Ask your parents to set up household rules")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.2))
                            }
                        }
                        .padding(.top, 40)
                    }
                }.padding(16)
            }
        }
        .task {
            if let fid = auth.familyId {
                await familyStore.load(familyId: fid)
                details = familyStore.family?.houseDetails
            }
        }
    }

    // MARK: - Today's Summary (child only)
    @ViewBuilder
    private func todaySummary(_ d: HouseDetails) -> some View {
        let summaryItems = buildTodaySummary(d)
        if !summaryItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Today's Duties", systemImage: "calendar").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                ForEach(summaryItems, id: \.self) { item in
                    HStack(spacing: 8) {
                        Circle().fill(Color.neonGreen).frame(width: 6, height: 6)
                        Text(item).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white)
                    }
                }
            }.gameCard(glow: .neonGreen.opacity(0.4))
        }
    }

    private func buildTodaySummary(_ d: HouseDetails) -> [String] {
        var items: [String] = []
        // Bin duty
        if let bin = d.binSchedule, bin.collectionDays.contains(todayDay),
           let current = rotationChild(bin.rotationChildren, weekly: true),
           isMyTurn(current) {
            items.append("Your turn for bin collection today!")
        }
        // Pet duties
        if let pets = d.pets {
            for pet in pets {
                if let wc = pet.walkRotationChildren, let current = rotationChild(wc), isMyTurn(current) {
                    items.append("Your turn to walk \(pet.name)")
                }
                if let lc = pet.litterRotationChildren, let current = rotationChild(lc), isMyTurn(current) {
                    items.append("Your turn for \(pet.name)'s litter")
                }
            }
        }
        // Gaming today
        if let gaming = d.gamingSchedule, let mySchedule = gaming[auth.userId ?? ""] {
            let todayRules = mySchedule.rules.filter { $0.days.contains(todayDay) }
            for rule in todayRules {
                items.append("\(rule.device.uppercased()): \(Int(rule.hours))hr allowed today")
            }
        }
        return items
    }

    // MARK: - Bin Section
    @ViewBuilder
    private func binSection(_ bin: BinSchedule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bin Collection", systemImage: "trash.fill").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.self) { day in
                    let active = bin.collectionDays.contains(day)
                    Text(String(day.prefix(2)).uppercased())
                        .font(.system(size: 10, weight: .black)).foregroundStyle(active ? .black : .white.opacity(0.3))
                        .frame(width: 32, height: 32).background(active ? Color.neonGreen : Color.gameCardLight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            if !bin.rotationChildren.isEmpty, let current = rotationChild(bin.rotationChildren, weekly: true) {
                HStack(spacing: 6) {
                    Text("This week:")
                        .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                    Text(memberName(current))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isMyTurn(current) ? .neonGreen : .white)
                    if isMyTurn(current) {
                        Text("(You!)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                    }
                }
                // Rotation sequence
                Text(bin.rotationChildren.map { memberName($0) }.joined(separator: " → "))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.neonGreen.opacity(0.5))
            }
        }.gameCard(glow: .neonGreen.opacity(0.3))
    }

    // MARK: - Pet Section
    @ViewBuilder
    private func petSection(_ pets: [Pet]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pet Care", systemImage: "pawprint.fill").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonOrange)
            ForEach(pets) { pet in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(pet.name) (\(pet.type))").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    if let wc = pet.walkRotationChildren, !wc.isEmpty, let current = rotationChild(wc) {
                        HStack(spacing: 4) {
                            Text("Walk today:").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                            Text(memberName(current)).font(.system(size: 12, weight: .bold)).foregroundStyle(isMyTurn(current) ? .neonGreen : .neonOrange)
                            if isMyTurn(current) { Text("(You!)").font(.system(size: 10, weight: .bold)).foregroundStyle(.neonGreen) }
                        }
                    }
                    if let lc = pet.litterRotationChildren, !lc.isEmpty, let current = rotationChild(lc) {
                        HStack(spacing: 4) {
                            Text("Litter today:").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                            Text(memberName(current)).font(.system(size: 12, weight: .bold)).foregroundStyle(isMyTurn(current) ? .neonGreen : .neonOrange)
                            if isMyTurn(current) { Text("(You!)").font(.system(size: 10, weight: .bold)).foregroundStyle(.neonGreen) }
                        }
                    }
                }
                .padding(10).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }.gameCard(glow: .neonOrange.opacity(0.3))
    }

    // MARK: - Play Time & Gaming (role-filtered)
    @ViewBuilder
    private func gamingSection(_ gaming: [String: GamingConfig]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(auth.isChild ? "My Play Time" : "Play Time & Gaming", systemImage: "gamecontroller.fill")
                .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)

            ForEach(Array(gaming.keys.sorted()), id: \.self) { childId in
                if auth.isParent || childId == auth.userId {
                    let config = gaming[childId]!
                    VStack(alignment: .leading, spacing: 6) {
                        if auth.isParent {
                            Text(memberName(childId)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)
                        }
                        ForEach(config.rules.indices, id: \.self) { i in
                            let rule = config.rules[i]
                            let isToday = rule.days.contains(todayDay)
                            let isWeekendOnly = Set(rule.days).isSubset(of: ["friday", "saturday", "sunday"])
                            let deviceIcon = deviceIconName(rule.device)

                            HStack(spacing: 8) {
                                Image(systemName: deviceIcon).font(.system(size: 14))
                                    .foregroundStyle(isToday ? .neonPurple : .white.opacity(0.3))
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if isToday { Circle().fill(Color.neonGreen).frame(width: 6, height: 6) }
                                        Text(rule.device.uppercased()).font(.system(size: 11, weight: .black, design: .rounded))
                                            .foregroundStyle(isToday ? .neonPurple : .white.opacity(0.4))
                                        if isWeekendOnly {
                                            Text("WEEKENDS").font(.system(size: 8, weight: .black, design: .rounded))
                                                .foregroundStyle(.neonOrange).padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color.neonOrange.opacity(0.15)).clipShape(Capsule())
                                        }
                                    }
                                    Text(rule.days.map { String($0.prefix(3)).capitalized }.joined(separator: ", "))
                                        .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                                }

                                Spacer()

                                Text("\(Int(rule.hours))hr").font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(isToday ? .neonPurple : .white.opacity(0.4))
                            }
                            .padding(8).background(isToday ? Color.neonPurple.opacity(0.1) : Color.gameCardLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Today's summary for this child
                        let todayRules = config.rules.filter { $0.days.contains(todayDay) }
                        if auth.isChild {
                            if todayRules.isEmpty {
                                Text("No screen time today — time for outdoor play!")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.3))
                            } else {
                                let totalHours = todayRules.reduce(0.0) { $0 + $1.hours }
                                Text("Today: \(Int(totalHours))hr total across \(todayRules.count) device\(todayRules.count > 1 ? "s" : "")")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.neonPurple.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }.gameCard(glow: .neonPurple.opacity(0.3))
    }

    private func deviceIconName(_ device: String) -> String {
        switch device.lowercased() {
        case "pc": return "desktopcomputer"
        case "console": return "gamecontroller.fill"
        case "tablet": return "ipad"
        case "vr": return "visionpro"
        case "tv": return "tv.fill"
        case "outdoor": return "figure.run"
        default: return "gamecontroller"
        }
    }
}

import SwiftUI

/// ⛲ By the Fountain — kid's view of earned play time.
///
/// Phase 1: a pond (representing earned hours), four device chips
/// (TV / Console / Tablet / VR), and a help line that explains the
/// earn rate. Default earn rate: 15 min per watered chore. No hard
/// chore-gate by default — empty pond is the only friction.
struct FountainView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @Environment(\.scenePhase) private var scenePhase

    @State private var pollTask: Task<Void, Never>?

    /// Default earn rate: 15 minutes of pond per watered chore.
    /// Will be parent-configurable in the Codex later.
    private let earnRatePerChore: Int = 15

    /// Daily caps (defaults; will be configurable). Weekday = 120m, weekend = 180m.
    private var dailyCapMinutes: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7 ? 180 : 120
    }

    private var earnedTodayMinutes: Int {
        let watered = choreStore.todaysChores.filter {
            $0.userId == auth.userId &&
            ($0.status == .approved || $0.status == .completed)
        }.count
        return min(watered * earnRatePerChore, dailyCapMinutes)
    }

    var body: some View {
        ZStack {
            skyGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer().frame(height: 16)
                pondView
                Spacer().frame(height: 12)
                helpLine
                Spacer().frame(height: 16)
                roomsGrid
                Spacer()
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("By the fountain")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.fountainInk)
                Text("\(scenicSubtitle) · earn 15 minutes per flower")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.fountainInkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private var pondView: some View {
        ZStack {
            // Pond gradient
            Capsule()
                .fill(RadialGradient(
                    colors: [Color(red: 0.58, green: 0.78, blue: 0.86),
                             Color(red: 0.42, green: 0.63, blue: 0.74),
                             Color(red: 0.30, green: 0.49, blue: 0.60)],
                    center: .center, startRadius: 30, endRadius: 130))
                .frame(width: 240, height: 130)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        .blur(radius: 1)
                )

            // Centre label
            VStack(spacing: 2) {
                Text(timeString(earnedTodayMinutes))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                Text("earned today")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            // Subtle ripple
            Capsule()
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                .frame(width: 70, height: 30)
                .modifier(RippleAnim())
        }
        .padding(.top, 6)
    }

    private var helpLine: some View {
        Text(helpText)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.fountainInkSoft)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private var roomsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            roomChip(name: "Telly", emoji: "📺", quota: "free with family", isSpecial: true)
            roomChip(name: "Console", emoji: "🎮",
                     quota: earnedTodayMinutes > 0 ? "\(earnedTodayMinutes / 2)m left" : "earn first")
            roomChip(name: "Tablet", emoji: "📱",
                     quota: earnedTodayMinutes > 0 ? "\(earnedTodayMinutes / 2)m left" : "earn first")
            roomChip(name: "VR", emoji: "🥽", quota: vrQuota, isVR: true)
        }
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private func roomChip(name: String, emoji: String, quota: String, isSpecial: Bool = false, isVR: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(emoji).font(.system(size: 26))
            Text(name)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.fountainInk)
            Text(quota)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(isVR && !isVRWeekend ? Color(red: 0.66, green: 0.50, blue: 0.35) : Color.fountainInkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(roomBackground(isSpecial: isSpecial, isVR: isVR))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isVR ? Color(red: 0.76, green: 0.55, blue: 0.85).opacity(0.55) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func roomBackground(isSpecial: Bool, isVR: Bool) -> some View {
        if isVR {
            return AnyView(LinearGradient(
                colors: [Color(red: 0.80, green: 0.70, blue: 0.92).opacity(0.55),
                         Color(red: 1.0, green: 0.93, blue: 0.78).opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        }
        return AnyView(Color.white.opacity(0.7))
    }

    // MARK: - Helpers

    private var helpText: String {
        let watered = choreStore.todaysChores.filter {
            $0.userId == auth.userId && ($0.status == .approved || $0.status == .completed)
        }.count
        let total = choreStore.todaysChores.filter { $0.userId == auth.userId }.count
        if total == 0 {
            return "No flowers today — see your garden."
        }
        if watered == 0 {
            return "Water a flower to fill the pond. Each one is worth 15 minutes."
        }
        let remaining = total - watered
        if remaining > 0 {
            return "You've watered \(watered) of \(total). \(remaining) more would earn \(remaining * earnRatePerChore) minutes."
        }
        return "All flowers watered today. Pond is full."
    }

    private var isVRWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    private var vrQuota: String {
        if !isVRWeekend { return "Sat / Sun only" }
        if earnedTodayMinutes == 0 { return "earn first" }
        return "\(earnedTodayMinutes / 4)m available"
    }

    private var skyGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.84, green: 0.91, blue: 0.94),
                     Color(red: 0.72, green: 0.83, blue: 0.88),
                     Color(red: 0.62, green: 0.76, blue: 0.83)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var scenicSubtitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8:   return "still water at dawn"
        case 8..<17:  return "calm under sunlight"
        case 17..<20: return "amber dusk on the pond"
        default:      return "stars on the surface"
        }
    }

    private func timeString(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Lifecycle helpers

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
}

private struct RippleAnim: ViewModifier {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.55
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 2.5).repeatForever(autoreverses: false)) {
                    scale = 1.6
                    opacity = 0
                }
            }
    }
}

private extension Color {
    static let fountainInk     = Color(red: 0.11, green: 0.20, blue: 0.27)
    static let fountainInkSoft = Color(red: 0.30, green: 0.42, blue: 0.51)
}

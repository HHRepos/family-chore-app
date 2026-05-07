import Foundation
import Observation

@Observable
class ChoreStore {
    var chores: [AssignedChore] = []
    var pendingApprovals: [AssignedChore] = []
    var isLoading = false

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var todaysChores: [AssignedChore] {
        chores.filter { normalizeDateString($0.dueDate) == todayString }
    }

    var activeQuests: [AssignedChore] {
        todaysChores.filter { $0.status == .pending || $0.status == .in_progress }
    }

    var completedQuests: [AssignedChore] {
        todaysChores.filter { $0.status == .completed || $0.status == .approved }
    }

    var totalTodayPoints: Int {
        todaysChores.reduce(0) { $0 + $1.points }
    }

    // Morning/Evening/Main sections
    var morningHabits: [AssignedChore] {
        todaysChores.filter { $0.isDailyHabit && $0.isMorning }
    }

    var eveningHabits: [AssignedChore] {
        todaysChores.filter { $0.isDailyHabit && $0.isEvening }
    }

    var mainChores: [AssignedChore] {
        todaysChores.filter { !$0.isDailyHabit }
    }

    var activeMorningHabits: [AssignedChore] { morningHabits.filter { $0.status == .pending || $0.status == .in_progress } }
    var activeEveningHabits: [AssignedChore] { eveningHabits.filter { $0.status == .pending || $0.status == .in_progress } }
    var activeMainChores: [AssignedChore] { mainChores.filter { $0.status == .pending || $0.status == .in_progress } }

    var morningComplete: Bool { morningHabits.allSatisfy { $0.status == .completed || $0.status == .approved } && !morningHabits.isEmpty }
    var eveningComplete: Bool { eveningHabits.allSatisfy { $0.status == .completed || $0.status == .approved } && !eveningHabits.isEmpty }

    /// Normalize date strings like "2026-04-09T00:00:00.000Z" to "2026-04-09"
    private func normalizeDateString(_ date: String) -> String {
        if date.count > 10 { return String(date.prefix(10)) }
        return date
    }

    // MARK: - Loading

    func loadUserChores(userId: String) async {
        isLoading = true
        do {
            chores = try await APIClient.shared.getUserChores(userId)
        } catch {
            print("Failed to load chores: \(error)")
        }
        isLoading = false
    }

    func loadFamilyChores(familyId: String) async {
        isLoading = true
        do {
            chores = try await APIClient.shared.getFamilyChores(familyId)
        } catch {
            print("Failed to load family chores: \(error)")
        }
        isLoading = false
    }

    func loadApprovals(familyId: String) async {
        do {
            pendingApprovals = try await APIClient.shared.getPendingApprovals(familyId)
        } catch {
            print("Failed to load approvals: \(error)")
        }
    }

    // MARK: - Actions

    func startChore(_ chore: AssignedChore) async {
        try? await APIClient.shared.updateChoreStatus(chore.assignedChoreId, status: "in_progress")
    }

    func completeChore(_ chore: AssignedChore) async {
        try? await APIClient.shared.updateChoreStatus(chore.assignedChoreId, status: "completed")
    }

    func approveChore(_ chore: AssignedChore) async {
        try? await APIClient.shared.approveChore(chore.assignedChoreId)
    }

    func rejectChore(_ chore: AssignedChore) async {
        try? await APIClient.shared.rejectChore(chore.assignedChoreId)
    }

    func transferChore(_ chore: AssignedChore, toUserId: String) async {
        try? await APIClient.shared.transferChore(chore.assignedChoreId, toUserId: toUserId)
    }

    func requestSupport(_ chore: AssignedChore, helperUserId: String) async {
        try? await APIClient.shared.requestSupport(chore.assignedChoreId, helperUserId: helperUserId)
    }
}

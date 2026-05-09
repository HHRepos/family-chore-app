import SwiftUI

struct QuestDetailView: View {
    @Environment(ChoreStore.self) private var choreStore
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    let chore: AssignedChore
    var onComplete: () -> Void = {}
    @State private var isActing = false
    @State private var showSiblingPicker: SiblingPickerMode?

    enum SiblingPickerMode: Identifiable {
        case transfer, support
        var id: String { self == .transfer ? "t" : "s" }
    }

    /// Eligible recipients for transfer / support: every other family member
    /// who is part of the chore rotation (siblings + any parent who has opted
    /// in via Settings → Join Chore Rotation).
    private var siblings: [FamilyMember] {
        familyStore.members.filter { $0.userId != auth.userId && $0.inChoreRotation }
    }

    private var difficultyColor: Color {
        switch chore.difficultyTier {
        case .easy: return .rookieGreen
        case .medium: return .proYellow
        case .hard: return .legendRed
        }
    }

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28)).foregroundStyle(.white.opacity(0.3))
                    }
                    Spacer()
                }

                Spacer()

                ZStack {
                    Circle().fill(difficultyColor.opacity(0.15)).frame(width: 100, height: 100)
                    Image(systemName: "scroll.fill").font(.system(size: 44)).foregroundStyle(difficultyColor).neonGlow(difficultyColor, radius: 16)
                }

                Text(chore.choreName).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white).multilineTextAlignment(.center)

                if let desc = chore.description, !desc.isEmpty {
                    Text(desc).font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
                }

                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(chore.difficultyTier.label).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(difficultyColor)
                        Text("Difficulty").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                    }
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(.neonYellow)
                            Text("\(chore.points)").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.neonYellow)
                        }
                        Text("XP Reward").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                    }
                }.padding(.vertical, 16)

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    // pending or in_progress → single "Mission Complete!" button (no
                    // separate Accept step). Most chores auto-approve so the points
                    // award on this single tap; the rest go to the parent for review.
                    if chore.status == .pending || chore.status == .in_progress {
                        Button("Mission Complete!") {
                            Task {
                                isActing = true
                                await choreStore.completeChore(chore)
                                onComplete()
                                dismiss()
                            }
                        }
                        .buttonStyle(NeonButtonStyle(color: .neonGreen))
                        .disabled(isActing)

                        // Daily habits (brush teeth, etc) and pet routines aren't
                        // transferable — they're things only YOU can do.
                        let isPersonal = chore.choreType == "daily_habit" || chore.choreType == "routine"
                        if !siblings.isEmpty && !isPersonal {
                            HStack(spacing: 12) {
                                Button { showSiblingPicker = .transfer } label: {
                                    Label("Transfer", systemImage: "arrow.right.arrow.left")
                                }.buttonStyle(SecondaryButtonStyle())

                                Button { showSiblingPicker = .support } label: {
                                    Label("Ask Help", systemImage: "heart.fill")
                                }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    } else if chore.status == .completed {
                        Text("Awaiting Approval").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.neonBlue)
                    } else if chore.status == .approved {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Approved!")
                        }.font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                    }
                }
            }
            .padding(24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $showSiblingPicker) { mode in
            SiblingPickerSheet(mode: mode, chore: chore, siblings: siblings) {
                dismiss()
            }
        }
    }
}

// MARK: - Sibling Picker
struct SiblingPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mode: QuestDetailView.SiblingPickerMode
    let chore: AssignedChore
    let siblings: [FamilyMember]
    let onDone: () -> Void
    @State private var isActing = false
    @State private var success = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer().frame(height: 20)
                Image(systemName: mode == .transfer ? "arrow.right.arrow.left.circle.fill" : "heart.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(mode == .transfer ? .neonOrange : .neonPink)
                    .neonGlow(mode == .transfer ? .neonOrange : .neonPink, radius: 12)

                Text(mode == .transfer ? "Transfer Quest" : "Ask for Help")
                    .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)

                Text(mode == .transfer
                     ? "They get the quest and ALL the XP"
                     : "You both share the quest — XP split 50/50")
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4)).multilineTextAlignment(.center).padding(.horizontal, 24)

                if success {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done!")
                    }.font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen).padding(.top, 20)
                } else {
                    VStack(spacing: 10) {
                        ForEach(siblings) { sibling in
                            Button {
                                isActing = true
                                Task {
                                    do {
                                        if mode == .transfer {
                                            try await APIClient.shared.transferChore(chore.assignedChoreId, toUserId: sibling.userId)
                                        } else {
                                            try await APIClient.shared.requestSupport(chore.assignedChoreId, helperUserId: sibling.userId)
                                        }
                                        success = true
                                        try? await Task.sleep(for: .seconds(1))
                                        dismiss()
                                        onDone()
                                    } catch { isActing = false }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.neonPurple.opacity(0.2)).frame(width: 44, height: 44)
                                        Text(sibling.firstName.prefix(1).uppercased())
                                            .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sibling.firstName).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        Text(mode == .transfer ? "Transfer to \(sibling.firstName)" : "Ask \(sibling.firstName) for help")
                                            .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.2))
                                }
                                .gameCard(glow: (mode == .transfer ? Color.neonOrange : Color.neonPink).opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .disabled(isActing)
                        }
                    }.padding(.horizontal, 16)
                }

                Button("Cancel") { dismiss() }
                    .font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
        }
        .presentationDetents([.medium])
    }
}

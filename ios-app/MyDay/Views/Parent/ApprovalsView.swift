import SwiftUI

struct ApprovalsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(ShopStore.self) private var shop
    @State private var approving: String?
    @State private var confirmApprove: AssignedChore?
    @State private var confirmReject: AssignedChore?
    @State private var successMessage: String?

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.neonGreen)
                            .neonGlow(.neonGreen, radius: 16)
                        Text("Approvals")
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(choreStore.pendingApprovals.count) awaiting review")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }.padding(.top, 16)

                    // Success banner
                    if let msg = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.neonGreen)
                            Text(msg).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                        }
                        .gameCard(glow: .neonGreen.opacity(0.4))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if choreStore.pendingApprovals.isEmpty && successMessage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.neonGreen.opacity(0.3))
                            Text("All caught up!").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                        }.padding(.top, 40)
                    }

                    ForEach(choreStore.pendingApprovals) { chore in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(chore.choreName).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    if let name = chore.firstName {
                                        Text(name).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.neonPurple)
                                    }
                                    HStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.neonYellow)
                                            Text("\(chore.points) pts").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                        }
                                        let tier = DifficultyTier(rawValue: chore.difficulty) ?? .easy
                                        Text(tier.label).font(.system(size: 10, weight: .heavy, design: .rounded))
                                            .foregroundStyle(tier == .easy ? .rookieGreen : tier == .medium ? .proYellow : .legendRed)
                                        Text(chore.dueDate.prefix(10)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                                    }
                                    if let transferType = chore.transferType {
                                        HStack(spacing: 4) {
                                            Image(systemName: transferType == "transfer" ? "arrow.right.arrow.left" : "heart.fill").font(.system(size: 10))
                                            Text(transferType == "transfer" ? "Transferred" : "Support (50/50)").font(.system(size: 10, weight: .bold, design: .rounded))
                                        }.foregroundStyle(transferType == "transfer" ? .neonOrange : .neonPink)
                                    }
                                }
                                Spacer()
                            }

                            HStack(spacing: 10) {
                                Button { confirmApprove = chore } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill"); Text("Approve")
                                    }.font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Color.neonGreen).clipShape(RoundedRectangle(cornerRadius: 10))
                                }.disabled(approving == chore.assignedChoreId)

                                Button { confirmReject = chore } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle.fill"); Text("Reject")
                                    }.font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 10))
                                }.disabled(approving == chore.assignedChoreId)
                            }
                        }.gameCard(glow: .neonGreen.opacity(0.3))
                    }

                    if !choreStore.pendingApprovals.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tips").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonBlue)
                            Text("• Approve chores to award points to your children").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                            Text("• Reject sends the chore back for the child to redo").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                            Text("• Support chores split points 50/50 between helpers").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        }.gameCard(glow: .neonBlue.opacity(0.2))
                    }
                }.padding(16)
            }
            .refreshable { if let fid = auth.familyId { await choreStore.loadApprovals(familyId: fid) } }
        }
        .task { if let fid = auth.familyId { await choreStore.loadApprovals(familyId: fid) } }
        .alert("Approve Chore", isPresented: Binding(get: { confirmApprove != nil }, set: { if !$0 { confirmApprove = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Approve & Award \(confirmApprove?.points ?? 0) pts") {
                guard let chore = confirmApprove else { return }
                Task {
                    approving = chore.assignedChoreId
                    await choreStore.approveChore(chore)
                    withAnimation { successMessage = "Approved! \(chore.points) points awarded to \(chore.firstName ?? "child")" }
                    if let fid = auth.familyId {
                        await choreStore.loadApprovals(familyId: fid)
                        await choreStore.loadFamilyChores(familyId: fid)
                        if let uid = auth.userId {
                            await shop.loadAll(userId: uid, familyId: fid)
                        }
                    }
                    approving = nil
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { successMessage = nil }
                }
            }
        } message: {
            Text("Approve '\(confirmApprove?.choreName ?? "")' and award \(confirmApprove?.points ?? 0) points?")
        }
        .alert("Reject Chore", isPresented: Binding(get: { confirmReject != nil }, set: { if !$0 { confirmReject = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Reject", role: .destructive) {
                guard let chore = confirmReject else { return }
                Task {
                    approving = chore.assignedChoreId
                    await choreStore.rejectChore(chore)
                    withAnimation { successMessage = "Rejected — \(chore.firstName ?? "child") will need to redo it" }
                    if let fid = auth.familyId {
                        await choreStore.loadApprovals(familyId: fid)
                        await choreStore.loadFamilyChores(familyId: fid)
                    }
                    approving = nil
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { successMessage = nil }
                }
            }
        } message: {
            Text("Reject '\(confirmReject?.choreName ?? "")'? The child will need to redo it.")
        }
    }
}

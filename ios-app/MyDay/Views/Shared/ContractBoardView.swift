import SwiftUI

struct ContractBoardView: View {
    @Environment(AuthManager.self) private var auth
    @State private var jobs: [Job] = []
    @State private var isLoading = true
    @State private var showCreateContract = false
    @State private var showPitchContract = false
    @State private var selectedJob: Job?
    @State private var applyJob: Job?

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Contract Board").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white)
                            Text(auth.isParent ? "Post contracts for your heroes" : "Pick up contracts for extra loot")
                                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        if auth.isParent {
                            Button { showCreateContract = true } label: {
                                Image(systemName: "plus.circle.fill").font(.system(size: 32)).foregroundStyle(.neonOrange)
                            }
                        } else {
                            // Pitch your own contract — clearer affordance than the
                            // old lightbulb icon (testers said it didn't read as
                            // "tap to propose").
                            Button { showPitchContract = true } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.pencil.circle.fill").font(.system(size: 24))
                                    Text("Propose").font(.system(size: 13, weight: .black, design: .rounded))
                                }
                                .foregroundStyle(.neonYellow)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Color.neonYellow.opacity(0.12))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.neonYellow.opacity(0.3), lineWidth: 1))
                            }
                        }
                    }.padding(.top, 8)

                    if jobs.isEmpty && !isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "target").font(.system(size: 48)).foregroundStyle(.white.opacity(0.15))
                            Text("No contracts yet").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            if auth.isParent {
                                Text("Tap + to post your first contract")
                                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.neonOrange.opacity(0.5))
                            }
                        }.padding(.top, 60)
                    }

                    // Kid proposals section (parent sees these)
                    let proposals = jobs.filter { $0.status == "proposed" }
                    if auth.isParent && !proposals.isEmpty {
                        Text("PROPOSALS FROM KIDS").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.neonYellow.opacity(0.6))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(proposals) { proposal in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(proposal.title).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Spacer()
                                    Text("PITCHED").font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(.neonYellow).padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.neonYellow.opacity(0.15)).clipShape(Capsule())
                                }
                                Text("by \(proposal.postedByName ?? "?")").font(.system(size: 12, weight: .medium)).foregroundStyle(.neonPurple)
                                if let pitch = proposal.pitchReason, !pitch.isEmpty {
                                    Text("\"\(pitch)\"").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5)).italic()
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: proposal.rewardType == "cash" ? "banknote.fill" : "star.fill")
                                        .foregroundStyle(proposal.rewardType == "cash" ? .neonGreen : .neonYellow)
                                    Text("Asking: \(RewardFormat.format(amount: proposal.proposedPrice ?? proposal.rewardAmount, type: proposal.rewardType))")
                                        .font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(.neonYellow)
                                }
                                HStack(spacing: 10) {
                                    Button {
                                        Task {
                                            try? await APIClient.shared.approveProposal(proposal.jobId)
                                            await loadJobs()
                                        }
                                    } label: {
                                        HStack(spacing: 4) { Image(systemName: "checkmark.circle.fill"); Text("Approve") }
                                            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                                            .background(Color.neonGreen).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    Button {
                                        Task {
                                            try? await APIClient.shared.rejectProposal(proposal.jobId)
                                            await loadJobs()
                                        }
                                    } label: {
                                        HStack(spacing: 4) { Image(systemName: "xmark.circle.fill"); Text("Reject") }
                                            .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                                            .background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }.gameCard(glow: .neonYellow.opacity(0.4))
                        }
                    }

                    // Grouped by section
                    let openJobs = jobs.filter { $0.status == "open" }
                    let myActiveJobs = auth.isChild ? jobs.filter { $0.assignedTo == auth.userId && ($0.status == "assigned" || $0.status == "completed") } : []
                    let otherJobs = jobs.filter { j in
                        !openJobs.contains(where: { $0.jobId == j.jobId }) &&
                        !myActiveJobs.contains(where: { $0.jobId == j.jobId })
                    }

                    if !openJobs.isEmpty {
                        Text("OPEN CONTRACTS").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(openJobs) { job in
                        ContractCard(job: job, isParent: auth.isParent, userId: auth.userId ?? "",
                            onAccept: {
                                guard auth.isChild else { return }
                                Task {
                                    try? await APIClient.shared.applyToJob(job.jobId, reason: nil, bidAmount: nil)
                                    await loadJobs()
                                }
                            },
                            onApply: {
                                guard auth.isChild else { return }
                                applyJob = job
                            },
                            onComplete: {
                                guard auth.isChild else { return }
                                Task {
                                    try? await APIClient.shared.completeJob(job.jobId)
                                    await loadJobs()
                                }
                            },
                            onConfirm: {
                                guard auth.isParent else { return }
                                Task {
                                    try? await APIClient.shared.confirmJob(job.jobId)
                                    await loadJobs()
                                }
                            },
                            onViewApps: {
                                guard auth.isParent else { return }
                                selectedJob = job
                            }
                        )
                    }

                    if !myActiveJobs.isEmpty {
                        Text("MY ACTIVE CONTRACTS").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    ForEach(myActiveJobs) { job in
                        ContractCard(job: job, isParent: auth.isParent, userId: auth.userId ?? "",
                            onAccept: {}, onApply: {},
                            onComplete: { Task { try? await APIClient.shared.completeJob(job.jobId); await loadJobs() } },
                            onConfirm: {}, onViewApps: {}
                        )
                    }

                    if !otherJobs.isEmpty {
                        Text(auth.isParent ? "ALL CONTRACTS" : "OTHER CONTRACTS").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                    ForEach(otherJobs) { job in
                        ContractCard(job: job, isParent: auth.isParent, userId: auth.userId ?? "",
                            onAccept: {}, onApply: {},
                            onComplete: {},
                            onConfirm: { guard auth.isParent else { return }; Task { try? await APIClient.shared.confirmJob(job.jobId); await loadJobs() } },
                            onViewApps: {}
                        )
                    }
                }.padding(16)
            }
        }
        .task { await loadJobs() }
        .refreshable { await loadJobs() }
        .sheet(isPresented: $showCreateContract) { CreateContractView { await loadJobs() } }
        .sheet(isPresented: $showPitchContract) { PitchContractView { await loadJobs() } }
        .sheet(item: $applyJob) { job in ApplyContractSheet(job: job) { await loadJobs() } }
        .sheet(item: $selectedJob) { job in ContractApplicationsSheet(job: job) { await loadJobs() } }
    }

    private func loadJobs() async {
        guard let fid = auth.familyId else { return }
        do { jobs = try await APIClient.shared.getJobs(fid) } catch {}
        isLoading = false
    }
}

// MARK: - Contract Card (role-aware)
struct ContractCard: View {
    let job: Job
    let isParent: Bool
    let userId: String
    let onAccept: () -> Void
    let onApply: () -> Void
    let onComplete: () -> Void
    let onConfirm: () -> Void
    let onViewApps: () -> Void
    @State private var expanded = false

    private var statusColor: Color {
        switch job.status {
        case "open": return .neonGreen
        case "assigned": return .neonBlue
        case "completed": return .neonYellow
        case "confirmed": return .neonPurple
        default: return .neonRed
        }
    }

    private var isAssignedToMe: Bool {
        !isParent && job.assignedTo == userId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title + status (always visible, tappable to expand)
            Button { withAnimation(.spring(response: 0.3)) { expanded.toggle() } } label: {
                HStack {
                    Text(job.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text(job.status.uppercased()).font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(statusColor).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusColor.opacity(0.15)).clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.2))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
            }.buttonStyle(.plain)

            if let desc = job.description, !desc.isEmpty {
                Text(desc).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(expanded ? nil : 2)
            }

            // Info row
            HStack(spacing: 12) {
                // Reward
                HStack(spacing: 4) {
                    Image(systemName: job.rewardType == "cash" ? "banknote.fill" : "star.fill")
                        .foregroundStyle(job.rewardType == "cash" ? .neonGreen : .neonYellow)
                    Text(RewardFormat.format(amount: job.rewardAmount, type: job.rewardType))
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(job.rewardType == "cash" ? .neonGreen : .neonYellow)
                }

                // Due date
                if let due = job.dueDate {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 11))
                        Text(due.prefix(10)).font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.white.opacity(0.4))
                }

                // Parent-only: application count
                if isParent && job.jobType == "application" {
                    HStack(spacing: 3) {
                        Image(systemName: "person.3.fill").font(.system(size: 11))
                        Text("\(job.applicationCount ?? 0) applied").font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.white.opacity(0.4))
                }

                // Show who's assigned
                if let name = job.assignedToName {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill").font(.system(size: 11))
                        Text(name).font(.system(size: 11, weight: .medium))
                    }.foregroundStyle(.neonBlue)
                }
            }

            if expanded {
            // Child-only: type indicator for open jobs
            if !isParent && job.status == "open" {
                HStack(spacing: 4) {
                    Image(systemName: job.jobType == "open" ? "bolt.fill" : "doc.text.fill").font(.system(size: 10))
                    Text(job.jobType == "open" ? "First come, first served" : "Apply with a reason")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }.foregroundStyle(.white.opacity(0.3))
            }

            // CHILD ACTIONS
            if !isParent {
                if job.status == "open" {
                    if job.jobType == "open" {
                        Button("Accept Contract", action: onAccept).buttonStyle(NeonButtonStyle(color: .neonOrange))
                    } else {
                        Button("Apply", action: onApply).buttonStyle(NeonButtonStyle(color: .neonPurple))
                    }
                }
                if isAssignedToMe && job.status == "assigned" {
                    Button("Mark Complete", action: onComplete).buttonStyle(NeonButtonStyle(color: .neonGreen))
                }
                if isAssignedToMe && job.status == "completed" {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill").font(.system(size: 12))
                        Text("Waiting for parent to confirm...")
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.neonYellow)
                    .padding(10).background(Color.neonYellow.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if isAssignedToMe && job.status == "confirmed" {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                        Text(job.rewardType == "cash" ? "\(RewardFormat.cash(job.rewardAmount)) confirmed! Ask your parent to hand it over." : "\(Int(job.rewardAmount)) points earned!")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.neonGreen)
                    .padding(10).background(Color.neonGreen.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if job.status == "expired" {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 14))
                        Text("Contract expired. Points deducted for not completing on time.")
                    }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.neonRed)
                    .padding(10).background(Color.neonRed.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // PARENT ACTIONS
            if isParent {
                if job.status == "completed" {
                    Button("Confirm & Award", action: onConfirm).buttonStyle(NeonButtonStyle(color: .neonGreen))
                }
                if job.jobType == "application" && job.status == "open" && (job.applicationCount ?? 0) > 0 {
                    Button("View Applications", action: onViewApps).buttonStyle(SecondaryButtonStyle())
                }
            }
            } // end if expanded
        }
        .gameCard(glow: statusColor.opacity(0.4))
    }
}

// MARK: - Create Contract (Parent only)
struct CreateContractView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let onCreated: () async -> Void
    @State private var title = ""
    @State private var desc = ""
    @State private var rewardType = "points"
    @State private var rewardAmount = "50"
    @State private var jobType = "open"
    @State private var dueDate = Date().addingTimeInterval(7 * 86400)
    @State private var hasDueDate = false
    @State private var isCreating = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            // Guard: parent only
            if !auth.isParent {
                Text("Only parents can create contracts")
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Post Contract").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.top, 20)

                        GameTextField(icon: "target", placeholder: "Contract title", text: $title)
                        GameTextField(icon: "text.alignleft", placeholder: "Description", text: $desc)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading) {
                                Text("Reward").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                                Picker("", selection: $rewardType) {
                                    Text("Points").tag("points"); Text("Cash").tag("cash")
                                }.pickerStyle(.segmented)
                            }
                            VStack(alignment: .leading) {
                                Text("Amount").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                                GameTextField(icon: "number", placeholder: "50", text: $rewardAmount)
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("Type").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            Picker("", selection: $jobType) {
                                Text("Open (first come)").tag("open")
                                Text("Application").tag("application")
                            }.pickerStyle(.segmented)

                            if jobType == "open" {
                                Text("Any child can instantly claim this contract")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.3))
                            } else {
                                Text("Children apply with a reason — you pick the winner")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                        }

                        // Due date
                        Toggle("Set due date", isOn: $hasDueDate)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .tint(.neonOrange)

                        if hasDueDate {
                            DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.neonOrange)
                        }

                        Button("Post Contract") {
                            isCreating = true
                            let f = DateFormatter()
                            f.dateFormat = "yyyy-MM-dd"
                            Task {
                                try? await APIClient.shared.createJob(
                                    auth.familyId ?? "", title: title, description: desc,
                                    rewardType: rewardType, rewardAmount: Double(rewardAmount) ?? 50,
                                    jobType: jobType, dueDate: hasDueDate ? f.string(from: dueDate) : nil
                                )
                                await onCreated()
                                dismiss()
                            }
                        }
                        .buttonStyle(NeonButtonStyle(color: .neonOrange))
                        .disabled(title.isEmpty || isCreating)

                        Button("Cancel") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                    }.padding(20)
                }
            }
        }
    }
}

// MARK: - Apply Sheet (Child only)
struct ApplyContractSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let job: Job
    let onDone: () async -> Void
    @State private var reason = ""
    @State private var bid = ""
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            if auth.isParent {
                Text("Only children can apply for contracts")
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                VStack(spacing: 16) {
                    Text("Apply for Contract").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.top, 20)
                    Text(job.title).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.neonOrange)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why are you the best hero for this?").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        GameTextField(icon: "text.quote", placeholder: "Your reason", text: $reason)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bid (optional — suggest a different reward)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        GameTextField(icon: "number", placeholder: "Your bid amount", text: $bid)
                    }

                    Button("Submit Application") {
                        isSubmitting = true
                        Task {
                            try? await APIClient.shared.applyToJob(job.jobId, reason: reason.isEmpty ? nil : reason, bidAmount: Double(bid))
                            await onDone(); dismiss()
                        }
                    }.buttonStyle(NeonButtonStyle(color: .neonPurple)).disabled(isSubmitting)

                    Button("Cancel") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(20)
            }
        }
    }
}

// MARK: - Applications Sheet (Parent only)
struct ContractApplicationsSheet: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let job: Job
    let onDone: () async -> Void
    @State private var apps: [JobApplication] = []
    @State private var assigning: String?

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()

            if !auth.isParent {
                Text("Only parents can view applications")
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Applications").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white).padding(.top, 20)
                        Text(job.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.neonOrange)

                        if apps.isEmpty {
                            Text("No applications yet").font(.system(size: 14)).foregroundStyle(.white.opacity(0.3)).padding(.top, 40)
                        }

                        ForEach(apps) { app in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(app.firstName ?? "?").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    if let age = app.age { Text("age \(age)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)) }
                                    Spacer()
                                    if app.status == "pending" {
                                        Button("Pick Winner") {
                                            assigning = app.applicationId
                                            Task {
                                                try? await APIClient.shared.assignJob(job.jobId, applicationId: app.applicationId)
                                                await onDone(); dismiss()
                                            }
                                        }
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(Color.neonOrange).clipShape(Capsule())
                                        .disabled(assigning == app.applicationId)
                                    } else {
                                        Text(app.status.uppercased()).font(.system(size: 10, weight: .black))
                                            .foregroundStyle(app.status == "accepted" ? .neonGreen : .neonRed)
                                    }
                                }
                                if let reason = app.reason, !reason.isEmpty {
                                    Text("\"\(reason)\"").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                                }
                                if let bid = app.bidAmount {
                                    Text("Bid: \(Int(bid)) \(job.rewardType == "cash" ? "$" : "pts")")
                                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)
                                }
                            }.gameCard(glow: .neonOrange.opacity(0.3))
                        }

                        Button("Done") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                    }.padding(20)
                }
            }
        }
        .task {
            guard auth.isParent else { return }
            do { apps = try await APIClient.shared.getJobApplications(job.jobId) } catch {}
        }
    }
}

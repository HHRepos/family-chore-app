import SwiftUI

struct PitchContractView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let onCreated: () async -> Void
    @State private var title = ""
    @State private var desc = ""
    @State private var rewardType = "points"
    @State private var price = "50"
    @State private var pitch = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var hasDueDate = true
    @State private var isSubmitting = false
    @State private var error: String?

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.neonYellow)
                            .neonGlow(.neonYellow, radius: 16)
                        Text("Pitch a Contract")
                            .font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Text("Propose a job to your parents and name your price!")
                            .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }.padding(.top, 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("What will you do?").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        GameTextField(icon: "briefcase.fill", placeholder: "e.g. Wash the car", text: $title)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Describe the work").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        GameTextField(icon: "text.alignleft", placeholder: "What exactly will you do?", text: $desc)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reward Type").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            Picker("", selection: $rewardType) {
                                Text("Points").tag("points"); Text("Cash").tag("cash")
                            }.pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your Price").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            GameTextField(icon: rewardType == "cash" ? "dollarsign" : "star.fill", placeholder: "50", text: $price)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your Pitch").font(.system(size: 12, weight: .bold)).foregroundStyle(.neonYellow.opacity(0.6))
                        Text("Why should your parent approve this? Sell it!").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                        GameTextField(icon: "megaphone.fill", placeholder: "I'll do an amazing job because...", text: $pitch)
                    }

                    // Due date
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $hasDueDate) {
                            Text("Set a due date").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                        }
                        .toggleStyle(.switch)
                        .tint(.neonYellow)
                        if hasDueDate {
                            DatePicker("Due", selection: $dueDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .tint(.neonYellow)
                        }
                    }.gameCard(glow: .neonYellow.opacity(0.15))

                    // Economics preview
                    VStack(spacing: 6) {
                        HStack {
                            Text("You'll earn:").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text(RewardFormat.format(amount: Double(price) ?? 0, type: rewardType))
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundStyle(rewardType == "cash" ? .neonGreen : .neonYellow)
                        }
                        Text("If your parent approves")
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.2))
                    }.gameCard(glow: .neonYellow.opacity(0.2))

                    if let error {
                        Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.neonRed)
                    }

                    Button(isSubmitting ? "Sending Pitch..." : "Send Pitch") {
                        isSubmitting = true
                        Task {
                            do {
                                try await APIClient.shared.pitchContract(
                                    auth.familyId ?? "", title: title, description: desc,
                                    rewardType: rewardType, proposedPrice: Double(price) ?? 50,
                                    pitchReason: pitch,
                                    dueDate: hasDueDate ? Self.dueDateFormatter.string(from: dueDate) : nil
                                )
                                await onCreated()
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                            isSubmitting = false
                        }
                    }
                    .buttonStyle(NeonButtonStyle(color: .neonYellow))
                    .disabled(title.isEmpty || pitch.isEmpty || isSubmitting)
                    .opacity(title.isEmpty || pitch.isEmpty ? 0.5 : 1)

                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(20)
            }
        }
    }
}

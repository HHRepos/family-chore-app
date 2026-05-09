import SwiftUI

/// Free-tier avatar customization sheet. Lets the user cycle through preset
/// hair, accessories, clothing colors, and skin tones — each one writes back
/// to the user's `avatar_customizations` array on the backend. Items the
/// future shop will lock behind points get added here as new entries with
/// an `unlocked` predicate; the data model and call site stay the same.
struct AvatarConfigView: View {
    @Environment(\.dismiss) private var dismiss
    let userId: String
    let initialCustomizations: [String]
    var onSaved: ([String]) -> Void = { _ in }

    @State private var customizations: [String]
    @State private var isSaving = false
    @State private var error: String?

    init(userId: String, initialCustomizations: [String], onSaved: @escaping ([String]) -> Void = { _ in }) {
        self.userId = userId
        self.initialCustomizations = initialCustomizations
        self.onSaved = onSaved
        self._customizations = State(initialValue: initialCustomizations)
    }

    /// Lookup: pull the current value for `key:value` items.
    private func value(for key: String) -> String {
        customizations
            .first { $0.hasPrefix("\(key):") }
            .flatMap { $0.split(separator: ":", maxSplits: 1).map(String.init).last }
            ?? ""
    }

    private func setValue(_ value: String, for key: String) {
        customizations.removeAll { $0.hasPrefix("\(key):") }
        if !value.isEmpty {
            customizations.append("\(key):\(value)")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.gameBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Live preview
                        AvatarView(
                            seed: userId,
                            size: 180,
                            customizations: customizations
                        )
                        .neonGlow(.neonPurple, radius: 18)
                        .padding(.top, 24)

                        section(
                            title: "Hair",
                            icon: "scissors",
                            key: "hair",
                            options: AvatarConfigView.hairStyles
                        )
                        section(
                            title: "Glasses",
                            icon: "eyeglasses",
                            key: "glasses",
                            options: AvatarConfigView.glasses
                        )
                        section(
                            title: "Hat",
                            icon: "hat.cap.fill",
                            key: "hat",
                            options: AvatarConfigView.hats
                        )
                        section(
                            title: "Mouth",
                            icon: "mouth.fill",
                            key: "mouth",
                            options: AvatarConfigView.mouths
                        )
                        colorSection(
                            title: "Hair colour",
                            icon: "paintbrush.fill",
                            key: "hairColor",
                            colors: AvatarConfigView.hairColors
                        )
                        colorSection(
                            title: "Clothing colour",
                            icon: "tshirt.fill",
                            key: "clothingColor",
                            colors: AvatarConfigView.clothingColors
                        )
                        colorSection(
                            title: "Skin tone",
                            icon: "person.fill",
                            key: "skinColor",
                            colors: AvatarConfigView.skinColors
                        )

                        if let error {
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.neonRed)
                        }

                        // Reset
                        Button("Reset to default") {
                            customizations = []
                        }
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(16)
                    .padding(.bottom, 80)
                }
            }
            .navigationTitle("Customize avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .fontWeight(.bold)
                        .disabled(isSaving || customizations == initialCustomizations)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        error = nil
        let toSave = customizations
        Task {
            do {
                try await APIClient.shared.updateAvatar(userId, customizations: toSave)
                await MainActor.run {
                    onSaved(toSave)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = "Couldn't save — \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, icon: String, key: String, options: [(value: String, label: String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.neonPurple)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.value) { opt in
                        let isSelected = value(for: key) == opt.value
                        Button { setValue(opt.value, for: key) } label: {
                            Text(opt.label)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? .black : .white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.neonPurple : Color.gameCardLight)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.neonPurple : .white.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
            }
        }
        .gameCard(glow: .neonPurple.opacity(0.2))
    }

    @ViewBuilder
    private func colorSection(title: String, icon: String, key: String, colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.neonPurple)
            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    let isSelected = value(for: key) == hex
                    Button { setValue(hex, for: key) } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(isSelected ? Color.neonPurple : .white.opacity(0.15), lineWidth: isSelected ? 3 : 1))
                            .scaleEffect(isSelected ? 1.08 : 1)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                    }
                }
            }
        }
        .gameCard(glow: .neonPurple.opacity(0.2))
    }
}

// MARK: - Preset libraries (pixel-art style)
extension AvatarConfigView {
    static let hairStyles: [(value: String, label: String)] = [
        ("", "Default"),
        ("short01", "Short A"),
        ("short02", "Short B"),
        ("short03", "Short C"),
        ("short04", "Short D"),
        ("short05", "Short E"),
        ("long01", "Long A"),
        ("long02", "Long B"),
        ("long03", "Long C"),
        ("long04", "Long D"),
        ("long05", "Long E")
    ]
    static let glasses: [(value: String, label: String)] = [
        ("", "None"),
        ("variant01", "Round"),
        ("variant02", "Square"),
        ("variant03", "Aviator"),
        ("variant04", "Star"),
        ("variant05", "VR")
    ]
    static let hats: [(value: String, label: String)] = [
        ("", "None"),
        ("variant01", "Cap A"),
        ("variant02", "Cap B"),
        ("variant03", "Beanie"),
        ("variant04", "Headband"),
        ("variant05", "Crown"),
        ("variant06", "Top hat")
    ]
    static let mouths: [(value: String, label: String)] = [
        ("", "Default"),
        ("happy01", "Smile"),
        ("happy02", "Grin"),
        ("happy03", "Laugh"),
        ("happy04", "Wink"),
        ("sad01", "Frown"),
        ("sad02", "Worried")
    ]
    static let hairColors: [String] = [
        "000000", "5b3e26", "8d5524", "c68642", "e6b87d", "ffd1a4", "8b3a3a", "5e60ce"
    ]
    static let clothingColors: [String] = [
        "6dbdb1", "ed7d3a", "5e94c4", "97a4b3", "ac6651", "f0a83a", "6b4f8e", "3fb950"
    ]
    static let skinColors: [String] = [
        "f8d4b4", "edb98a", "d08b5b", "ae5d29", "694d3d"
    ]
}

private extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xff) / 255
        let g = Double((rgb >> 8) & 0xff) / 255
        let b = Double(rgb & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}

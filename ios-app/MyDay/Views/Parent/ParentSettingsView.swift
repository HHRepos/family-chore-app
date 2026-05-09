import SwiftUI

struct ParentSettingsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(ChoreStore.self) private var choreStore
    @State private var showManageRewards = false
    @State private var showManageChores = false
    @State private var showManageFamily = false
    @State private var showAddChild = false
    @State private var showLinkChild = false
    @State private var showBinConfig = false
    @State private var showPetConfig = false
    @State private var showGamingConfig = false
    @State private var showRoomScan = false
    @State private var showLogoutConfirm = false
    @State private var showDeleteFamilyConfirm = false
    @State private var showEditFamily = false
    @State private var participates = false
    @State private var participatesLoaded = false
    @State private var showAvatarConfig = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // Profile
                    VStack(spacing: 8) {
                        Button { showAvatarConfig = true } label: {
                            AvatarView(
                                seed: auth.userId ?? "parent",
                                size: 80,
                                customizations: auth.user?.avatarCustomizations ?? [],
                                fallbackInitial: auth.user?.firstName
                            )
                        }
                        .buttonStyle(.plain)
                        Text(auth.user?.firstName ?? "").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        Text(auth.user?.email ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        Button("Customize avatar") { showAvatarConfig = true }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.neonPurple)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Color.neonPurple.opacity(0.12))
                            .clipShape(Capsule())
                    }.padding(.top, 12)

                    // Family Management
                    VStack(spacing: 2) {
                        SettingsRow(icon: "person.3.fill", title: "Manage Family Members", subtitle: "\(familyStore.members.count) members in family", color: .neonGreen) {
                            showManageFamily = true
                        }
                    }

                    // Chore & Reward Management
                    VStack(spacing: 2) {
                        SettingsRow(icon: "scroll.fill", title: "Manage Chores", subtitle: "Add chores for the family", color: .neonBlue) {
                            showManageChores = true
                        }
                        SettingsRow(icon: "gift.fill", title: "Manage Rewards", subtitle: "Add, edit, delete shop rewards", color: .neonPurple) {
                            showManageRewards = true
                        }
                    }

                    // Household Routines
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Household Routines")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.leading, 4).padding(.bottom, 4)

                        SettingsRow(icon: "trash.fill", title: "Bin Collection", subtitle: "Collection days & rotation", color: .neonGreen) {
                            showBinConfig = true
                        }
                        SettingsRow(icon: "pawprint.fill", title: "Pet Care", subtitle: "Walk & litter rotations", color: .neonOrange) {
                            showPetConfig = true
                        }
                        SettingsRow(icon: "gamecontroller.fill", title: "Gaming Schedule", subtitle: "Device, days & hours per child", color: .neonPurple) {
                            showGamingConfig = true
                        }
                        SettingsRow(icon: "camera.viewfinder", title: "Scan Rooms", subtitle: "AI-detect rooms & create chores", color: .neonBlue) {
                            showRoomScan = true
                        }
                    }

                    // Participation toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Join Chore Rotation").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            Text("Include me in weekly chores").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer()
                        Toggle("", isOn: $participates)
                            .tint(.neonGreen)
                            .onChange(of: participates) { _, val in
                                // Skip the initial value emission from .task —
                                // only react to actual user-driven toggles.
                                guard participatesLoaded else { return }
                                Task {
                                    try? await APIClient.shared.setParticipation(auth.userId ?? "", participate: val)
                                    // Re-distribute and reload so the parent shows up in (or
                                    // disappears from) the chore rotation immediately.
                                    if let fid = auth.familyId {
                                        try? await APIClient.shared.distributeChores(fid)
                                        await choreStore.loadFamilyChores(familyId: fid)
                                        await familyStore.load(familyId: fid)
                                    }
                                }
                            }
                    }.gameCard()

                    // Home / Family Info
                    VStack(spacing: 2) {
                        SettingsRow(icon: "house.fill", title: "Manage Home", subtitle: familyStore.family?.familyName ?? "Edit family name & house type", color: .neonBlue) {
                            showEditFamily = true
                        }
                    }

                    // Danger Zone
                    VStack(spacing: 10) {
                        Text("DANGER ZONE").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.neonRed.opacity(0.4))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading)

                        Button("Delete Family & All Data") { showDeleteFamilyConfirm = true }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.neonRed)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.neonRed.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonRed.opacity(0.2), lineWidth: 1))

                        Text("This permanently deletes the family, all members, chores, rewards, contracts, and data. Cannot be undone.")
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.2))
                    }

                    // Logout
                    Button("Log Out") { showLogoutConfirm = true }.buttonStyle(NeonButtonStyle(color: .neonRed))

                    // Version
                    Text("Version 1.0.0")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity)
                }.padding(16)
            }
        }
        .alert("Log Out", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { auth.fullLogout() }
        } message: {
            Text("Are you sure you want to log out?")
        }
        .alert("Delete Family", isPresented: $showDeleteFamilyConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task {
                    guard let fid = auth.familyId else { return }
                    try? await APIClient.shared.deleteFamily(fid)
                    auth.fullLogout()
                }
            }
        } message: {
            Text("This will permanently delete your family, ALL member accounts, chores, rewards, contracts, and all data. This cannot be undone.\n\nEveryone will be logged out.")
        }
        .sheet(isPresented: $showEditFamily) { EditFamilyView() }
        .task {
            if let uid = auth.userId {
                let result = try? await APIClient.shared.getParticipation(uid)
                participates = result?["participate_in_chores"] ?? false
                participatesLoaded = true
            }
        }
        .sheet(isPresented: $showManageRewards) { ManageRewardsView() }
        .sheet(isPresented: $showManageChores) { ManageChoresView() }
        .sheet(isPresented: $showManageFamily) { ManageFamilyView() }
        .sheet(isPresented: $showAddChild) { AddChildView() }
        .sheet(isPresented: $showLinkChild) { LinkChildView() }
        .sheet(isPresented: $showBinConfig) { BinConfigView() }
        .sheet(isPresented: $showPetConfig) { PetConfigView() }
        .sheet(isPresented: $showGamingConfig) { GamingConfigView() }
        .sheet(isPresented: $showRoomScan) { RoomScanView() }
        .sheet(isPresented: $showAvatarConfig) {
            AvatarConfigView(
                userId: auth.userId ?? "",
                initialCustomizations: auth.user?.avatarCustomizations ?? [],
                onSaved: { newConfig in
                    auth.user?.avatarCustomizations = newConfig
                }
            )
        }
    }
}

// MARK: - Edit Family (name + house type)
struct EditFamilyView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var familyName = ""
    @State private var houseType = "house"
    @State private var isSaving = false
    @State private var saved = false

    let houseTypes = [
        ("house", "House", "house.fill"),
        ("apartment", "Apartment", "building.2.fill"),
        ("condo", "Condo", "building.fill"),
        ("townhouse", "Townhouse", "house.lodge.fill")
    ]

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Manage Home").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Family Name").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        GameTextField(icon: "person.3.fill", placeholder: "Family name", text: $familyName)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Home Type").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(houseTypes, id: \.0) { type in
                                Button {
                                    houseType = type.0
                                } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: type.2).font(.system(size: 24))
                                            .foregroundStyle(houseType == type.0 ? .neonBlue : .white.opacity(0.3))
                                        Text(type.1).font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(houseType == type.0 ? .white : .white.opacity(0.4))
                                    }
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .background(houseType == type.0 ? Color.neonBlue.opacity(0.15) : Color.gameCardLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(houseType == type.0 ? Color.neonBlue.opacity(0.4) : .clear, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    if saved {
                        HStack { Image(systemName: "checkmark.circle.fill"); Text("Saved!") }
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.neonGreen)
                    }

                    Button(isSaving ? "Saving..." : "Save Changes") {
                        isSaving = true
                        Task {
                            try? await APIClient.shared.updateFamily(
                                auth.familyId ?? "",
                                name: familyName.isEmpty ? nil : familyName,
                                houseType: houseType
                            )
                            if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                            saved = true; isSaving = false
                            try? await Task.sleep(for: .seconds(1.5)); dismiss()
                        }
                    }
                    .buttonStyle(NeonButtonStyle(color: .neonBlue))
                    .disabled(isSaving)

                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(16)
            }
        }
        .onAppear {
            familyName = familyStore.family?.familyName ?? ""
            // Get house type from house_details if available
            houseType = "house" // default
        }
    }
}

struct SettingsRow: View {
    let icon: String; let title: String; let subtitle: String; let color: Color; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(color).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.2))
            }.gameCard(glow: color.opacity(0.2))
        }.buttonStyle(.plain)
    }
}

// MARK: - Add Child
// MARK: - Manage Family Members
struct ManageFamilyView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddChild = false
    @State private var showLinkChild = false
    @State private var editingChild: FamilyMember?
    @State private var editName = ""
    @State private var editAge = ""
    @State private var removingMember: FamilyMember?
    @State private var partnerCode: String?
    @State private var isGeneratingPartner = false
    @State private var roleChangeMember: FamilyMember?
    @State private var inviteCodes: [String: String] = [:] // childId → code
    @State private var generatingId: String?

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Manage Family Members").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    // Other parents/partners (not current user)
                    let otherParents = familyStore.members.filter { $0.role == "parent" && $0.userId != auth.userId }
                    if !otherParents.isEmpty {
                        Text("PARENTS / PARTNERS").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(otherParents) { parent in
                            HStack(spacing: 12) {
                                AvatarView(
                                    seed: parent.userId,
                                    size: 44,
                                    customizations: parent.avatarCustomizations,
                                    fallbackInitial: parent.firstName
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(parent.firstName).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Text("Parent").font(.system(size: 12, weight: .medium)).foregroundStyle(.neonBlue)
                                }
                                Spacer()
                                if parent.hasAccount == true {
                                    Button { roleChangeMember = parent } label: {
                                        Text("Role").font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(.neonBlue).padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(Color.neonBlue.opacity(0.1)).clipShape(Capsule())
                                    }
                                }
                                Button { removingMember = parent } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.neonRed.opacity(0.5))
                                }
                            }.gameCard(glow: .neonBlue.opacity(0.2))
                        }
                    }

                    if familyStore.children.isEmpty && otherParents.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.3").font(.system(size: 40)).foregroundStyle(.white.opacity(0.15))
                            Text("No other family members yet").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                        }.padding(.top, 40)
                    }

                    if !familyStore.children.isEmpty {
                        Text("CHILDREN").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                            .tracking(1).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Children list
                    ForEach(familyStore.children) { child in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AvatarView(
                                    seed: child.userId,
                                    size: 44,
                                    customizations: child.avatarCustomizations,
                                    fallbackInitial: child.firstName
                                )

                                // Name + Age
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.firstName).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    if let age = child.age {
                                        Text("Age \(age)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                                    }
                                }

                                Spacer()

                                // Status badge
                                if child.hasAccount == true {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.neonGreen).frame(width: 6, height: 6)
                                        Text("Linked").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.neonGreen.opacity(0.1)).clipShape(Capsule())
                                } else {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.neonOrange).frame(width: 6, height: 6)
                                        Text("No account").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.neonOrange)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.neonOrange.opacity(0.1)).clipShape(Capsule())
                                }
                            }

                            // Invite code section (if no account)
                            if child.hasAccount != true {
                                if let code = inviteCodes[child.userId] {
                                    VStack(spacing: 6) {
                                        Text("Invite code:").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.3))
                                        Text(code).font(.system(size: 22, weight: .black, design: .monospaced)).foregroundStyle(.neonGreen).tracking(3)
                                        HStack(spacing: 10) {
                                            Button {
                                                #if os(iOS)
                                                UIPasteboard.general.string = code
                                                #endif
                                            } label: {
                                                HStack(spacing: 4) { Image(systemName: "doc.on.doc").font(.system(size: 12)); Text("Copy") }
                                                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonGreen)
                                            }
                                            ShareLink(item: "Join our family on OMyDay! Invite code: \(code)") {
                                                HStack(spacing: 4) { Image(systemName: "square.and.arrow.up").font(.system(size: 12)); Text("Share") }
                                                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonBlue)
                                            }
                                        }
                                    }
                                    .padding(10).background(Color.neonGreen.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Button {
                                        generatingId = child.userId
                                        Task {
                                            do {
                                                let result = try await APIClient.shared.createChildInvitation(child.userId)
                                                if let code = result["invite_code"] {
                                                    inviteCodes[child.userId] = code
                                                }
                                            } catch {}
                                            generatingId = nil
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "envelope.badge.fill").font(.system(size: 14))
                                            Text(generatingId == child.userId ? "Generating..." : "Generate Invite Code")
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                        }.foregroundStyle(.neonGreen)
                                    }.disabled(generatingId == child.userId)
                                }
                            }

                            // Edit + Role + Remove
                            HStack(spacing: 16) {
                                Button {
                                    editingChild = child
                                    editName = child.firstName
                                    editAge = child.age != nil ? String(child.age!) : ""
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "pencil").font(.system(size: 12))
                                        Text("Edit").font(.system(size: 12, weight: .medium, design: .rounded))
                                    }.foregroundStyle(.white.opacity(0.3))
                                }
                                if child.hasAccount == true {
                                    Button { roleChangeMember = child } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 12))
                                            Text("Change Role").font(.system(size: 12, weight: .medium, design: .rounded))
                                        }.foregroundStyle(.neonBlue.opacity(0.6))
                                    }
                                }
                                Spacer()
                                Button { removingMember = child } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash").font(.system(size: 12))
                                        Text("Remove").font(.system(size: 12, weight: .medium, design: .rounded))
                                    }.foregroundStyle(.neonRed.opacity(0.5))
                                }
                            }
                        }
                        .gameCard(glow: child.hasAccount == true ? .neonGreen.opacity(0.2) : .neonOrange.opacity(0.2))
                    }

                    // Action buttons
                    VStack(spacing: 10) {
                        Button { showAddChild = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus").font(.system(size: 16))
                                Text("Add Another Child").font(.system(size: 14, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonGreen)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.neonGreen.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonGreen.opacity(0.2), lineWidth: 1))
                        }

                        Button { showLinkChild = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "link").font(.system(size: 16))
                                Text("Link Existing Child").font(.system(size: 14, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonBlue)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.neonBlue.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonBlue.opacity(0.15), lineWidth: 1))
                        }

                        Button { generatePartnerCode() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.badge.plus").font(.system(size: 16))
                                Text(partnerCode != nil ? "Partner Code: \(partnerCode!)" : isGeneratingPartner ? "Generating..." : "Invite Partner / Parent")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                            }.foregroundStyle(.neonPurple)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.neonPurple.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.neonPurple.opacity(0.15), lineWidth: 1))
                        }.disabled(isGeneratingPartner)

                        if let code = partnerCode {
                            VStack(spacing: 6) {
                                Text(code).font(.system(size: 28, weight: .black, design: .monospaced)).foregroundStyle(.neonPurple).tracking(4)
                                Text("Share with your partner — they enter this code to join").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                                HStack(spacing: 10) {
                                    Button {
                                        #if os(iOS)
                                        UIPasteboard.general.string = code
                                        #endif
                                    } label: {
                                        HStack(spacing: 4) { Image(systemName: "doc.on.doc").font(.system(size: 12)); Text("Copy") }
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.neonPurple)
                                    }
                                    ShareLink(item: "Join our family on OMyDay! Your invite code is: \(code)") {
                                        HStack(spacing: 4) { Image(systemName: "square.and.arrow.up").font(.system(size: 12)); Text("Share") }
                                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.neonBlue)
                                    }
                                }
                            }.gameCard(glow: .neonPurple.opacity(0.3))
                        }
                    }
                }.padding(16)
            }
        }
        .sheet(isPresented: $showAddChild) {
            AddChildView()
        }
        .sheet(isPresented: $showLinkChild) {
            LinkChildView()
        }
        .alert("Edit Child", isPresented: Binding(get: { editingChild != nil }, set: { if !$0 { editingChild = nil } })) {
            TextField("Name", text: $editName)
            TextField("Age", text: $editAge)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard let child = editingChild else { return }
                Task {
                    // Update child details via API
                    var body: [String: String] = ["first_name": editName]
                    if !editAge.isEmpty { body["age"] = editAge }
                    try? await APIClient.shared.requestVoid(.PATCH, "/users/\(child.userId)", body: body)
                    if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                }
            }
        } message: {
            Text("Update \(editingChild?.firstName ?? "")'s details")
        }
        .alert("Remove Member", isPresented: Binding(get: { removingMember != nil }, set: { if !$0 { removingMember = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                guard let member = removingMember, let fid = auth.familyId else { return }
                Task {
                    try? await APIClient.shared.removeFamilyMember(fid, memberId: member.userId)
                    await familyStore.load(familyId: fid)
                }
            }
        } message: {
            Text("Remove \(removingMember?.firstName ?? "") from the family? Their chores and data will be deleted. They can rejoin later with a code.")
        }
        .confirmationDialog(
            "Change Role for \(roleChangeMember?.firstName ?? "")",
            isPresented: Binding(get: { roleChangeMember != nil }, set: { if !$0 { roleChangeMember = nil } }),
            titleVisibility: .visible
        ) {
            let currentRole = roleChangeMember?.role ?? "child"
            let newRole = currentRole == "parent" ? "child" : "parent"
            Button("Change to \(newRole.capitalized)") {
                guard let member = roleChangeMember, let fid = auth.familyId else { return }
                Task {
                    try? await APIClient.shared.requestVoid(.PATCH, "/users/\(member.userId)", body: ["role": newRole])
                    await familyStore.load(familyId: fid)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let currentRole = roleChangeMember?.role ?? "child"
            let newRole = currentRole == "parent" ? "child" : "parent"
            Text("\(roleChangeMember?.firstName ?? "") is currently a \(currentRole). Change to \(newRole)? This will change what they see in the app.")
        }
    }

    private func generatePartnerCode() {
        isGeneratingPartner = true
        Task {
            do {
                guard let fid = auth.familyId else { return }
                let result: [String: String] = try await APIClient.shared.request(.POST, "/families/\(fid)/invite-parent")
                partnerCode = result["invite_code"]
            } catch {}
            isGeneratingPartner = false
        }
    }
}

struct AddChildView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var age = "8"
    @State private var isAdding = false
    @State private var inviteCode: String?
    @State private var childId: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if inviteCode == nil {
                        // Step 1: Add child
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus").font(.system(size: 36)).foregroundStyle(.neonGreen).neonGlow(.neonGreen, radius: 12)
                            Text("Add Child").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                        }.padding(.top, 20)

                        GameTextField(icon: "person.fill", placeholder: "Child's name", text: $name)
                        GameTextField(icon: "number", placeholder: "Age", text: $age)

                        if let error { Text(error).font(.system(size: 13, weight: .medium)).foregroundStyle(.neonRed) }

                        Button(isAdding ? "Adding..." : "Add & Generate Invite Code") {
                            isAdding = true; error = nil
                            Task {
                                do {
                                    // Step 1: Create child
                                    let result: [String: String] = try await APIClient.shared.request(.POST, "/families/\(auth.familyId ?? "")/members", body: [
                                        "first_name": name, "age": age, "role": "child"
                                    ])
                                    guard let cid = result["user_id"] else { error = "Failed to add child"; isAdding = false; return }
                                    childId = cid

                                    // Step 2: Auto-generate invitation
                                    let inv: [String: String] = try await APIClient.shared.request(.POST, "/children/\(cid)/invite")
                                    inviteCode = inv["invite_code"]

                                    if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                                } catch let err as APIError {
                                    error = err.errorDescription
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                isAdding = false
                            }
                        }.buttonStyle(NeonButtonStyle(color: .neonGreen)).disabled(name.isEmpty || isAdding)

                        Button("Cancel") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                    } else {
                        // Step 2: Show invite code
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.neonGreen).neonGlow(.neonGreen, radius: 16)
                            Text("\(name) added!").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        }.padding(.top, 20)

                        VStack(spacing: 8) {
                            Text("Their invite code:").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.4))
                            Text(inviteCode ?? "")
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundStyle(.neonGreen)
                                .neonGlow(.neonGreen, radius: 10)
                                .tracking(6)
                            Text("Expires in 7 days").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.25))
                        }
                        .gameCard(glow: .neonGreen.opacity(0.4))

                        Text("Tell \(name) to open the app and tap\n\"I have an invite code\"")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)

                        // Copy + Share buttons
                        HStack(spacing: 12) {
                            Button {
                                #if os(iOS)
                                UIPasteboard.general.string = inviteCode
                                #endif
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc").font(.system(size: 14))
                                    Text("Copy Code")
                                }
                            }.buttonStyle(SecondaryButtonStyle())

                            ShareLink(item: "Join our family on OMyDay! Your invite code is: \(inviteCode ?? "")") {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                                    Text("Share")
                                }
                            }.buttonStyle(NeonButtonStyle(color: .neonGreen))
                        }

                        Button("Done") { dismiss() }
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                            .padding(.top, 8)
                    }
                }.padding(20)
            }
        }
    }
}

// MARK: - Manage Rewards
struct ManageRewardsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var rewards: [Reward] = []
    @State private var name = ""; @State private var desc = ""; @State private var cost = "50"
    @State private var isAdding = false

    @FocusState private var addFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Manage Rewards").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    VStack(spacing: 10) {
                        GameTextField(icon: "gift.fill", placeholder: "Reward name", text: $name)
                            .focused($addFieldFocused)
                        GameTextField(icon: "text.alignleft", placeholder: "Description", text: $desc)
                            .focused($addFieldFocused)
                        GameTextField(icon: "star.fill", placeholder: "Point cost", text: $cost)
                            .focused($addFieldFocused)
                        Button("Add Reward") {
                            isAdding = true
                            addFieldFocused = false  // dismiss the keyboard immediately
                            Task {
                                try? await APIClient.shared.createReward(auth.familyId ?? "", name: name, description: desc, pointCost: Int(cost) ?? 50, childId: nil)
                                name = ""; desc = ""; cost = "50"
                                await loadRewards(); isAdding = false
                            }
                        }.buttonStyle(NeonButtonStyle(color: .neonPurple)).disabled(name.isEmpty || isAdding)
                    }.gameCard(glow: .neonPurple.opacity(0.3))

                    ForEach(rewards) { reward in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reward.rewardName).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.neonYellow)
                                    Text("\(reward.pointCost)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.neonYellow)
                                }
                            }
                            Spacer()
                            Button { Task {
                                try? await APIClient.shared.deleteReward(reward.rewardId)
                                await loadRewards()
                            }} label: {
                                Image(systemName: "trash.fill").font(.system(size: 14)).foregroundStyle(.neonRed.opacity(0.6))
                            }
                        }.gameCard()
                    }
                }.padding(16)
            }
        }
        .task { await loadRewards() }
    }

    private func loadRewards() async {
        guard let fid = auth.familyId else { return }
        do { rewards = try await APIClient.shared.getRewards(fid) } catch {}
    }
}

// MARK: - Manage Chores
struct ManageChoresView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ChoreStore.self) private var choreStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var desc = ""
    @State private var frequency = "daily"; @State private var difficulty = "easy"; @State private var points = "10"
    @State private var isAdding = false; @State private var success = false

    @FocusState private var addFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Add Chore").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    GameTextField(icon: "scroll.fill", placeholder: "Chore name", text: $name)
                        .focused($addFieldFocused)
                    GameTextField(icon: "text.alignleft", placeholder: "Description", text: $desc)
                        .focused($addFieldFocused)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Frequency").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            Picker("", selection: $frequency) {
                                Text("Daily").tag("daily"); Text("Weekly").tag("weekly")
                            }.pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading) {
                            Text("Difficulty").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            Picker("", selection: $difficulty) {
                                Text("Quick").tag("easy"); Text("Standard").tag("medium"); Text("Challenge").tag("hard")
                            }.pickerStyle(.segmented)
                        }
                    }

                    GameTextField(icon: "star.fill", placeholder: "Points", text: $points)
                        .focused($addFieldFocused)

                    if success {
                        HStack { Image(systemName: "checkmark.circle.fill"); Text("Added!") }
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.neonGreen)
                    }

                    Button("Add Chore") {
                        isAdding = true
                        addFieldFocused = false
                        Task {
                            try? await APIClient.shared.createChore(auth.familyId ?? "", name: name, description: desc, frequency: frequency, difficulty: difficulty, points: Int(points) ?? 10)
                            name = ""; desc = ""; success = true; isAdding = false
                            try? await Task.sleep(for: .seconds(2)); success = false
                        }
                    }.buttonStyle(NeonButtonStyle(color: .neonBlue)).disabled(name.isEmpty || isAdding)

                    // Redistribute button
                    Button {
                        Task {
                            guard let fid = auth.familyId else { return }
                            try? await APIClient.shared.distributeChores(fid)
                            if let fid = auth.familyId { await choreStore.loadFamilyChores(familyId: fid) }
                        }
                    } label: {
                        Label("Redistribute Weekly Chores", systemImage: "arrow.triangle.2.circlepath")
                    }.buttonStyle(SecondaryButtonStyle())
                }.padding(16)
            }
        }
    }
}

// MARK: - Bin Collection Config
struct BinConfigView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDays: Set<String> = []
    @State private var rotationChildIds: [String] = []
    @State private var isSaving = false
    @State private var saved = false

    let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Bin Collection").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    // Day selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection Days").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let day = weekdays[i]
                                Button { toggleDay(day) } label: {
                                    Text(dayLabels[i])
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(selectedDays.contains(day) ? .black : .white.opacity(0.4))
                                        .frame(width: 38, height: 38)
                                        .background(selectedDays.contains(day) ? Color.neonGreen : Color.gameCardLight)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }.gameCard(glow: .neonGreen.opacity(0.3))

                    // Rotation children
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rotation Children").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        ForEach(familyStore.children) { child in
                            let included = rotationChildIds.contains(child.userId)
                            Button {
                                if included { rotationChildIds.removeAll { $0 == child.userId } }
                                else { rotationChildIds.append(child.userId) }
                            } label: {
                                HStack {
                                    Text(child.firstName).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(included ? .neonGreen : .white.opacity(0.3))
                                }
                                .padding(12).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.gameCard()

                    if saved {
                        HStack { Image(systemName: "checkmark.circle.fill"); Text("Saved!") }
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.neonGreen)
                    }

                    Button("Save") { save() }.buttonStyle(NeonButtonStyle(color: .neonGreen)).disabled(isSaving)
                    Button("Cancel") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(16)
            }
        }
        .task { loadExisting() }
    }

    private func toggleDay(_ day: String) {
        if selectedDays.contains(day) { selectedDays.remove(day) }
        else { selectedDays.insert(day) }
    }

    private func loadExisting() {
        if let bin = familyStore.family?.houseDetails?.binSchedule {
            selectedDays = Set(bin.collectionDays)
            rotationChildIds = bin.rotationChildren
        }
    }

    private func save() {
        isSaving = true
        Task {
            let config: [String: Any] = [
                "bin_schedule": [
                    "collection_days": Array(selectedDays),
                    "rotation_children": rotationChildIds
                ]
            ]
            try? await APIClient.shared.updateFamilyConfig(auth.familyId ?? "", config: config)
            if let fid = auth.familyId { await familyStore.load(familyId: fid) }
            saved = true; isSaving = false
            try? await Task.sleep(for: .seconds(1)); dismiss()
        }
    }
}

// MARK: - Pet Care Config
struct PetConfigView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var petName = ""
    @State private var petType = "dog"
    @State private var walkChildren: [String] = []
    @State private var litterChildren: [String] = []
    @State private var isSaving = false

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Pet Care").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    // Existing pets
                    if let pets = familyStore.family?.houseDetails?.pets, !pets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Pets").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            ForEach(pets) { pet in
                                HStack {
                                    Image(systemName: pet.type == "dog" ? "dog.fill" : pet.type == "cat" ? "cat.fill" : "pawprint.fill")
                                        .foregroundStyle(.neonOrange)
                                    Text("\(pet.name) (\(pet.type))").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Spacer()
                                    Button {
                                        Task {
                                            let remaining = (familyStore.family?.houseDetails?.pets ?? []).filter { $0.id != pet.id }
                                            let dicts = remaining.map { p -> [String: Any] in
                                                var d: [String: Any] = ["id": p.id, "name": p.name, "type": p.type]
                                                if let wc = p.walkRotationChildren { d["walk_rotation_children"] = wc }
                                                if let lc = p.litterRotationChildren { d["litter_rotation_children"] = lc }
                                                return d
                                            }
                                            try? await APIClient.shared.updateFamilyConfig(auth.familyId ?? "", config: ["pets": dicts])
                                            if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                                        }
                                    } label: {
                                        Image(systemName: "trash.fill").font(.system(size: 14)).foregroundStyle(.neonRed.opacity(0.6))
                                    }
                                }
                                .padding(10).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }.gameCard(glow: .neonOrange.opacity(0.3))
                    }

                    // Add new pet
                    VStack(spacing: 10) {
                        Text("Add Pet").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                        GameTextField(icon: "pawprint.fill", placeholder: "Pet name", text: $petName)
                        Picker("Type", selection: $petType) {
                            Text("Dog").tag("dog"); Text("Cat").tag("cat"); Text("Other").tag("other")
                        }.pickerStyle(.segmented)

                        if petType == "dog" || petType == "other" {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Walk Rotation").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                                ForEach(familyStore.children) { child in
                                    let included = walkChildren.contains(child.userId)
                                    Button {
                                        if included { walkChildren.removeAll { $0 == child.userId } }
                                        else { walkChildren.append(child.userId) }
                                    } label: {
                                        HStack {
                                            Text(child.firstName).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                            Spacer()
                                            Image(systemName: included ? "checkmark.circle.fill" : "circle").foregroundStyle(included ? .neonGreen : .white.opacity(0.3))
                                        }.padding(8).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        if petType == "cat" {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Litter Rotation").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                                ForEach(familyStore.children) { child in
                                    let included = litterChildren.contains(child.userId)
                                    Button {
                                        if included { litterChildren.removeAll { $0 == child.userId } }
                                        else { litterChildren.append(child.userId) }
                                    } label: {
                                        HStack {
                                            Text(child.firstName).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                            Spacer()
                                            Image(systemName: included ? "checkmark.circle.fill" : "circle").foregroundStyle(included ? .neonGreen : .white.opacity(0.3))
                                        }.padding(8).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }

                        Button("Add Pet") {
                            isSaving = true
                            Task {
                                var existingPets = (familyStore.family?.houseDetails?.pets ?? []).map { pet -> [String: Any] in
                                    var p: [String: Any] = ["id": pet.id, "name": pet.name, "type": pet.type]
                                    if let wc = pet.walkRotationChildren { p["walk_rotation_children"] = wc }
                                    if let lc = pet.litterRotationChildren { p["litter_rotation_children"] = lc }
                                    return p
                                }
                                var newPet: [String: Any] = ["id": UUID().uuidString, "name": petName, "type": petType]
                                if !walkChildren.isEmpty { newPet["walk_rotation_children"] = walkChildren }
                                if !litterChildren.isEmpty { newPet["litter_rotation_children"] = litterChildren }
                                existingPets.append(newPet)
                                try? await APIClient.shared.updateFamilyConfig(auth.familyId ?? "", config: ["pets": existingPets])
                                if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                                petName = ""; isSaving = false; dismiss()
                            }
                        }.buttonStyle(NeonButtonStyle(color: .neonOrange)).disabled(petName.isEmpty || isSaving)
                    }.gameCard(glow: .neonOrange.opacity(0.3))

                    Button("Done") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(16)
            }
        }
    }
}

// MARK: - Gaming Config
struct GamingConfigView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(FamilyStore.self) private var familyStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChild: FamilyMember?
    @State private var device = "console"
    @State private var selectedDays: Set<String> = []
    @State private var hours = "2"
    @State private var isSaving = false

    let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    let devices = ["pc", "console", "tablet", "vr"]

    var body: some View {
        ZStack {
            Color.gameBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Gaming Schedule").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(.white.opacity(0.3)) }
                    }.padding(.top, 16)

                    // Child selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Child").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(familyStore.children) { child in
                                    ChildPickerChip(label: child.firstName, isSelected: selectedChild?.userId == child.userId) {
                                        selectedChild = child
                                    }
                                }
                            }
                        }
                    }

                    // Existing rules
                    if let gaming = familyStore.family?.houseDetails?.gamingSchedule, !gaming.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Rules").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                            ForEach(Array(gaming.keys.sorted()), id: \.self) { childId in
                                let config = gaming[childId]!
                                let childName = familyStore.members.first(where: { $0.userId == childId })?.firstName ?? "?"
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(childName).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.neonPurple)
                                    ForEach(config.rules.indices, id: \.self) { i in
                                        let rule = config.rules[i]
                                        HStack {
                                            Text(rule.device.uppercased()).font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                                            Text(rule.days.map { String($0.prefix(3)) }.joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                            Text("\(Int(rule.hours))hr").font(.system(size: 11, weight: .bold)).foregroundStyle(.neonPurple)
                                            Spacer()
                                            Button {
                                                Task {
                                                    var existing = familyStore.family?.houseDetails?.gamingSchedule ?? [:]
                                                    var rules = existing[childId]?.rules ?? []
                                                    rules.remove(at: i)
                                                    var schedDict: [String: Any] = [:]
                                                    for (key, val) in existing {
                                                        if key == childId { continue }
                                                        schedDict[key] = ["rules": val.rules.map { ["days": $0.days, "device": $0.device, "hours": $0.hours] }]
                                                    }
                                                    if !rules.isEmpty {
                                                        schedDict[childId] = ["rules": rules.map { ["days": $0.days, "device": $0.device, "hours": $0.hours] }]
                                                    }
                                                    try? await APIClient.shared.updateFamilyConfig(auth.familyId ?? "", config: ["gaming_schedule": schedDict])
                                                    if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                                                }
                                            } label: {
                                                Image(systemName: "trash.fill").font(.system(size: 12)).foregroundStyle(.neonRed.opacity(0.6))
                                            }
                                        }
                                        .padding(6).background(Color.gameCardLight).clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }.gameCard(glow: .neonPurple.opacity(0.2))
                    }

                    // Device
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        Picker("", selection: $device) {
                            ForEach(devices, id: \.self) { d in Text(d.uppercased()).tag(d) }
                        }.pickerStyle(.segmented)
                    }

                    // Days
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Allowed Days").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let day = weekdays[i]
                                Button {
                                    if selectedDays.contains(day) { selectedDays.remove(day) }
                                    else { selectedDays.insert(day) }
                                } label: {
                                    Text(dayLabels[i])
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(selectedDays.contains(day) ? .black : .white.opacity(0.4))
                                        .frame(width: 38, height: 38)
                                        .background(selectedDays.contains(day) ? Color.neonPurple : Color.gameCardLight)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    // Hours
                    GameTextField(icon: "clock.fill", placeholder: "Hours per session", text: $hours)

                    Button("Add Rule") {
                        guard let child = selectedChild else { return }
                        isSaving = true
                        Task {
                            var existing = familyStore.family?.houseDetails?.gamingSchedule ?? [:]
                            var config = existing[child.userId] ?? GamingConfig(rules: [])
                            let newRule = GamingRule(days: Array(selectedDays), device: device, hours: Double(hours) ?? 2)
                            var rules = config.rules
                            rules.append(newRule)

                            // Build full gaming schedule dict
                            var schedDict: [String: Any] = [:]
                            for (key, val) in existing {
                                if key == child.userId { continue }
                                schedDict[key] = ["rules": val.rules.map { ["days": $0.days, "device": $0.device, "hours": $0.hours] }]
                            }
                            schedDict[child.userId] = ["rules": rules.map { ["days": $0.days, "device": $0.device, "hours": $0.hours] }]

                            try? await APIClient.shared.updateFamilyConfig(auth.familyId ?? "", config: ["gaming_schedule": schedDict])
                            if let fid = auth.familyId { await familyStore.load(familyId: fid) }
                            selectedDays = []; isSaving = false; dismiss()
                        }
                    }.buttonStyle(NeonButtonStyle(color: .neonPurple)).disabled(selectedChild == nil || selectedDays.isEmpty || isSaving)

                    Button("Done") { dismiss() }.font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.3))
                }.padding(16)
            }
        }
    }
}

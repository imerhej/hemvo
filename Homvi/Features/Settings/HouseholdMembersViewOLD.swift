////  HouseholdMembersView.swift
////  Homvi
////  Redesigned with email invitation flow (premium only).
//
//internal import SwiftUI
//internal import Combine
//
//// MARK: - HouseholdMembersView
//struct HouseholdMembersView: View {
//
//    @EnvironmentObject var authVM: AuthViewModel
//    @Environment(\.dismiss) var dismiss
//    @StateObject private var scheduleVM = ScheduleViewModel()
//
//    @State private var showAddSheet     = false
//    @State private var showInviteSheet  = false
//    @State private var showPaywall      = false
//    @State private var memberToDelete: HouseholdMember? = nil
//    @State private var showDeleteAlert  = false
//    @State private var invites:          [HouseholdInvite] = []
//
//    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
//
//    // Premium = active subscription (not just trial)
//    private var hasPremium: Bool {
//        authVM.isSubscriptionActive && authVM.trialDaysRemaining == 0
//    }
//
//    var body: some View {
//        NavigationStack {
//            ZStack(alignment: .bottom) {
//                Color(hex: "#FAF7F2")!.ignoresSafeArea()
//
//                VStack(spacing: 0) {
//                    headerBar
//
//                    ScrollView(showsIndicators: false) {
//                        VStack(alignment: .leading, spacing: 22) {
//
//                            // ── Members section ───────────────
//                            if !scheduleVM.householdMembers.isEmpty {
//                                sectionLabel("MEMBERS · \(scheduleVM.householdMembers.count)")
//                                    .padding(.horizontal, 20)
//
//                                LazyVGrid(columns: columns, spacing: 14) {
//                                    ForEach(scheduleVM.householdMembers) { member in
//                                        MemberCard(member: member) {
//                                            memberToDelete = member
//                                            showDeleteAlert = true
//                                        }
//                                    }
//                                }
//                                .padding(.horizontal, 20)
//                            }
//
//                            // ── Pending invites section ───────
//                            let pending = invites.filter { $0.status == .pending && !$0.isExpired }
//                            if !pending.isEmpty {
//                                sectionLabel("PENDING INVITES · \(pending.count)")
//                                    .padding(.horizontal, 20)
//                                    .padding(.top, scheduleVM.householdMembers.isEmpty ? 16 : 0)
//
//                                VStack(spacing: 10) {
//                                    ForEach(pending) { invite in
//                                        InviteCard(invite: invite) {
//                                            HouseholdInviteService.shared.deleteInvite(id: invite.id)
//                                            loadInvites()
//                                        } onResend: {
//                                            HouseholdInviteService.shared.sendInviteEmail(
//                                                invite: invite,
//                                                senderName: authVM.currentUser?.firstName ?? "Homvi"
//                                            )
//                                        }
//                                    }
//                                }
//                                .padding(.horizontal, 20)
//                            }
//
//                            // ── Empty state ───────────────────
//                            if scheduleVM.householdMembers.isEmpty && pending.isEmpty {
//                                emptyState
//                                    .padding(.top, 60)
//                            }
//
//                            // ── Premium invite banner ─────────
//                            if !hasPremium {
//                                premiumBanner.padding(.horizontal, 20)
//                            }
//
//                            Spacer(minLength: 110)
//                        }
//                        .padding(.top, 18)
//                    }
//                }
//
//                // ── Action buttons ────────────────────────────
//                actionButtons.padding(.bottom, 32)
//            }
//            .navigationBarHidden(true)
//            .onAppear { loadInvites() }
//            .sheet(isPresented: $showAddSheet) {
//                AddMemberSheet(scheduleVM: scheduleVM)
//            }
//            .sheet(isPresented: $showInviteSheet) {
//                InviteMemberSheet(
//                    senderName: authVM.currentUser?.firstName ?? "Homvi"
//                ) { newInvite in
//                    HouseholdInviteService.shared.addInvite(newInvite)
//                    loadInvites()
//                }
//            }
//            .fullScreenCover(isPresented: $showPaywall) {
//                PaywallView()
//            }
//            .alert("Remove Member", isPresented: $showDeleteAlert) {
//                Button("Remove", role: .destructive) {
//                    if let m = memberToDelete {
//                        withAnimation { scheduleVM.deleteMember(m) }
//                    }
//                }
//                Button("Cancel", role: .cancel) { }
//            } message: {
//                Text("Remove \(memberToDelete?.name ?? "this member") from your household? They'll be unassigned from all tasks and events.")
//            }
//        }
//    }
//
//    // MARK: - Header
//    private var headerBar: some View {
//        ZStack {
//            Color.white
//            HStack(alignment: .center) {
//                VStack(alignment: .leading, spacing: 3) {
//                    Text("HOUSEHOLD")
//                        .font(.system(size: 10, weight: .heavy))
//                        .kerning(3)
//                        .foregroundColor(Color(hex: "#C8922A")!)
//                    Text("My Family")
//                        .font(.system(size: 26, weight: .black))
//                        .foregroundColor(Color(hex: "#1A1208")!)
//                }
//                Spacer()
//                Button { dismiss() } label: {
//                    Text("Done")
//                        .font(.system(size: 14, weight: .bold))
//                        .foregroundColor(Color(hex: "#C8922A")!)
//                        .padding(.horizontal, 16).padding(.vertical, 8)
//                        .background(Color(hex: "#F5E4C3")!)
//                        .cornerRadius(20)
//                }
//            }
//            .padding(.horizontal, 22)
//            .padding(.top, 52)
//            .padding(.bottom, 14)
//        }
//        .frame(height: 120)
//        .overlay(alignment: .bottom) {
//            Color(hex: "#E6DDD0")!.frame(height: 1)
//        }
//    }
//
//    // MARK: - Action Buttons (FAB row)
//    private var actionButtons: some View {
//        HStack(spacing: 12) {
//            // Add manually (always available)
//            Button { showAddSheet = true } label: {
//                HStack(spacing: 7) {
//                    Image(systemName: "person.badge.plus")
//                        .font(.system(size: 13, weight: .bold))
//                    Text("Add")
//                        .font(.system(size: 14, weight: .bold))
//                }
//                .foregroundColor(Color(hex: "#C8922A")!)
//                .padding(.horizontal, 20).padding(.vertical, 14)
//                .background(Color(hex: "#F5E4C3")!)
//                .cornerRadius(30)
//                .overlay(
//                    Capsule()
//                        .stroke(Color(hex: "#C8922A")!.opacity(0.3), lineWidth: 1)
//                )
//            }
//
//            // Invite via Email (premium only)
//            Button {
//                if hasPremium {
//                    showInviteSheet = true
//                } else {
//                    showPaywall = true
//                }
//            } label: {
//                HStack(spacing: 7) {
//                    Image(systemName: hasPremium ? "envelope.badge.fill" : "lock.fill")
//                        .font(.system(size: 13, weight: .bold))
//                    Text("Invite via Email")
//                        .font(.system(size: 14, weight: .bold))
//                }
//                .foregroundColor(.white)
//                .padding(.horizontal, 20).padding(.vertical, 14)
//                .background(
//                    Capsule()
//                        .fill(hasPremium ? Color(hex: "#C8922A")! : Color(hex: "#9B8F82")!)
//                        .shadow(color: hasPremium
//                                ? Color(hex: "#C8922A")!.opacity(0.4) : .clear,
//                                radius: 12, y: 5)
//                )
//            }
//        }
//    }
//
//    // MARK: - Premium Banner
//    private var premiumBanner: some View {
//        HStack(spacing: 12) {
//            ZStack {
//                RoundedRectangle(cornerRadius: 10)
//                    .fill(Color(hex: "#F5E4C3")!)
//                    .frame(width: 42, height: 42)
//                Image(systemName: "crown.fill")
//                    .font(.system(size: 18))
//                    .foregroundColor(Color(hex: "#C8922A")!)
//            }
//            VStack(alignment: .leading, spacing: 3) {
//                Text("Premium Feature")
//                    .font(.system(size: 13, weight: .bold))
//                    .foregroundColor(Color(hex: "#1A1208")!)
//                Text("Upgrade to invite family members via email and share your household.")
//                    .font(.system(size: 11, weight: .medium))
//                    .foregroundColor(Color(hex: "#7A6A55")!)
//            }
//            Spacer()
//            Button { showPaywall = true } label: {
//                Text("Upgrade")
//                    .font(.system(size: 12, weight: .heavy))
//                    .foregroundColor(.white)
//                    .padding(.horizontal, 12).padding(.vertical, 7)
//                    .background(Color(hex: "#C8922A")!)
//                    .cornerRadius(20)
//            }
//        }
//        .padding(14)
//        .background(Color.white)
//        .cornerRadius(16)
//        .overlay(
//            RoundedRectangle(cornerRadius: 16)
//                .stroke(Color(hex: "#C8922A")!.opacity(0.25), lineWidth: 1)
//        )
//        .shadow(color: Color(hex: "#1A1208")!.opacity(0.05), radius: 8, y: 3)
//    }
//
//    // MARK: - Section Label
//    private func sectionLabel(_ text: String) -> some View {
//        Text(text)
//            .font(.system(size: 10, weight: .heavy))
//            .kerning(1.5)
//            .foregroundColor(Color(hex: "#7A6A55")!)
//    }
//
//    // MARK: - Empty State
//    private var emptyState: some View {
//        VStack(spacing: 18) {
//            ZStack {
//                Circle().fill(Color(hex: "#F5E4C3")!).frame(width: 100, height: 100)
//                Image(systemName: "person.2.fill")
//                    .font(.system(size: 40))
//                    .foregroundColor(Color(hex: "#C8922A")!)
//            }
//            VStack(spacing: 8) {
//                Text("No Members Yet")
//                    .font(.system(size: 20, weight: .bold))
//                    .foregroundColor(Color(hex: "#1A1208")!)
//                Text("Add people manually or invite them\nvia email (Premium).")
//                    .font(.system(size: 14, weight: .medium))
//                    .foregroundColor(Color(hex: "#7A6A55")!)
//                    .multilineTextAlignment(.center)
//            }
//        }
//        .frame(maxWidth: .infinity)
//    }
//
//    private func loadInvites() {
//        invites = HouseholdInviteService.shared.loadInvites()
//    }
//}
//
//// MARK: - InviteCard
//struct InviteCard: View {
//    let invite:    HouseholdInvite
//    let onRevoke:  () -> Void
//    let onResend:  () -> Void
//
//    @State private var showRevokeAlert = false
//
//    var body: some View {
//        HStack(spacing: 14) {
//            // Avatar placeholder
//            ZStack {
//                Circle()
//                    .fill(Color(hex: invite.avatarColorHex)?.opacity(0.15) ?? Color.gray.opacity(0.15))
//                    .frame(width: 48, height: 48)
//                Circle()
//                    .stroke(Color(hex: invite.avatarColorHex) ?? .gray, lineWidth: 2)
//                    .frame(width: 48, height: 48)
//                Image(systemName: "envelope.fill")
//                    .font(.system(size: 16, weight: .semibold))
//                    .foregroundColor(Color(hex: invite.avatarColorHex) ?? .gray)
//            }
//
//            VStack(alignment: .leading, spacing: 4) {
//                Text(invite.name)
//                    .font(.system(size: 14, weight: .bold))
//                    .foregroundColor(Color(hex: "#1A1208")!)
//                Text(invite.email)
//                    .font(.system(size: 11, weight: .medium))
//                    .foregroundColor(Color(hex: "#7A6A55")!)
//                HStack(spacing: 6) {
//                    // Status pill
//                    HStack(spacing: 4) {
//                        Circle()
//                            .fill(Color.orange)
//                            .frame(width: 5, height: 5)
//                        Text("Pending")
//                            .font(.system(size: 9, weight: .heavy))
//                            .foregroundColor(.orange)
//                    }
//                    .padding(.horizontal, 7).padding(.vertical, 3)
//                    .background(Color.orange.opacity(0.1))
//                    .cornerRadius(20)
//
//                    // Invite code
//                    Text("Code: \(invite.code)")
//                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
//                        .foregroundColor(Color(hex: "#C8922A")!)
//                        .padding(.horizontal, 7).padding(.vertical, 3)
//                        .background(Color(hex: "#F5E4C3")!)
//                        .cornerRadius(20)
//                }
//            }
//
//            Spacer()
//
//            // Resend + revoke
//            VStack(spacing: 6) {
//                Button { onResend() } label: {
//                    Image(systemName: "arrow.clockwise")
//                        .font(.system(size: 12, weight: .bold))
//                        .foregroundColor(Color(hex: "#C8922A")!)
//                        .frame(width: 30, height: 30)
//                        .background(Color(hex: "#F5E4C3")!)
//                        .clipShape(Circle())
//                }
//                Button { showRevokeAlert = true } label: {
//                    Image(systemName: "xmark")
//                        .font(.system(size: 11, weight: .bold))
//                        .foregroundColor(.red)
//                        .frame(width: 30, height: 30)
//                        .background(Color.red.opacity(0.08))
//                        .clipShape(Circle())
//                }
//            }
//        }
//        .padding(14)
//        .background(Color.white)
//        .cornerRadius(16)
//        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
//        .shadow(color: Color(hex: "#1A1208")!.opacity(0.05), radius: 6, y: 2)
//        .alert("Revoke Invitation", isPresented: $showRevokeAlert) {
//            Button("Revoke", role: .destructive) { onRevoke() }
//            Button("Cancel", role: .cancel) { }
//        } message: {
//            Text("Cancel \(invite.name)'s invitation? The code \(invite.code) will no longer work.")
//        }
//    }
//}
//
//// MARK: - InviteMemberSheet
//struct InviteMemberSheet: View {
//    let senderName: String
//    let onSend: (HouseholdInvite) -> Void
//    @Environment(\.dismiss) var dismiss
//
//    @State private var name          = ""
//    @State private var email         = ""
//    @State private var role          = ""
//    @State private var selectedColor = HouseholdMember.sampleColors[1]
//    @State private var shakeTrigger: CGFloat = 0
//    @State private var generatedCode = HouseholdInviteService.generateCode()
//    @State private var isSent        = false
//    @FocusState private var focused: InviteField?
//    enum InviteField { case name, email }
//
//    private let roles = ["Spouse / Partner", "Child", "Parent", "Roommate", "Other"]
//
//    private var avatarColor: Color {
//        Color(hex: selectedColor) ?? Color(hex: "#2196F3")!
//    }
//    private var isValid: Bool { !name.isEmpty && isValidEmail(email) }
//
//    var body: some View {
//        NavigationStack {
//            ZStack {
//                Color(hex: "#FAF7F2")!.ignoresSafeArea()
//
//                if isSent {
//                    sentConfirmation
//                } else {
//                    ScrollView(showsIndicators: false) {
//                        VStack(spacing: 24) {
//
//                            // ── Envelope hero ─────────────────
//                            ZStack {
//                                Circle().fill(avatarColor.opacity(0.1)).frame(width: 110, height: 110)
//                                Circle().fill(avatarColor.opacity(0.18)).frame(width: 86, height: 86)
//                                Circle().fill(avatarColor).frame(width: 70, height: 70)
//                                    .shadow(color: avatarColor.opacity(0.4), radius: 12, y: 5)
//                                Image(systemName: "envelope.badge.fill")
//                                    .font(.system(size: 28, weight: .semibold))
//                                    .foregroundColor(.white)
//                            }
//                            .animation(.spring(response: 0.3), value: selectedColor)
//                            .padding(.top, 8)
//
//                            // ── Code preview ──────────────────
//                            VStack(spacing: 6) {
//                                Text("INVITE CODE")
//                                    .font(.system(size: 9, weight: .heavy))
//                                    .kerning(1.5)
//                                    .foregroundColor(Color(hex: "#7A6A55")!)
//                                HStack(spacing: 8) {
//                                    Text(generatedCode)
//                                        .font(.system(size: 28, weight: .black, design: .monospaced))
//                                        .foregroundColor(avatarColor)
//                                        .kerning(4)
//                                    Button {
//                                        generatedCode = HouseholdInviteService.generateCode()
//                                    } label: {
//                                        Image(systemName: "arrow.clockwise")
//                                            .font(.system(size: 14, weight: .bold))
//                                            .foregroundColor(Color(hex: "#7A6A55")!)
//                                    }
//                                }
//                            }
//                            .padding(14)
//                            .frame(maxWidth: .infinity)
//                            .background(Color.white)
//                            .cornerRadius(14)
//                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
//
//                            // ── Color swatches ────────────────
//                            HStack(spacing: 12) {
//                                ForEach(HouseholdMember.sampleColors, id: \.self) { hex in
//                                    let isSelected = selectedColor == hex
//                                    Button {
//                                        withAnimation(.spring(response: 0.2)) { selectedColor = hex }
//                                    } label: {
//                                        ZStack {
//                                            Circle().fill(Color(hex: hex) ?? .gray)
//                                                .frame(width: 32, height: 32)
//                                                .shadow(color: (Color(hex: hex) ?? .gray).opacity(0.4), radius: 4, y: 2)
//                                            if isSelected {
//                                                Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 32, height: 32)
//                                                Image(systemName: "checkmark")
//                                                    .font(.system(size: 9, weight: .black))
//                                                    .foregroundColor(.white)
//                                            }
//                                        }
//                                        .scaleEffect(isSelected ? 1.2 : 1.0)
//                                        .animation(.spring(response: 0.2), value: isSelected)
//                                    }
//                                    .buttonStyle(.plain)
//                                }
//                            }
//
//                            // ── Name field ────────────────────
//                            inviteField(
//                                label: "THEIR NAME",
//                                icon: "person.fill",
//                                placeholder: "e.g. Sarah",
//                                text: $name,
//                                field: .name,
//                                keyboard: .default,
//                                autocap: .words
//                            )
//
//                            // ── Email field ───────────────────
//                            inviteField(
//                                label: "THEIR EMAIL",
//                                icon: "envelope.fill",
//                                placeholder: "sarah@example.com",
//                                text: $email,
//                                field: .email,
//                                keyboard: .emailAddress,
//                                autocap: .never
//                            )
//
//                            // ── Role chips ────────────────────
//                            VStack(alignment: .leading, spacing: 10) {
//                                fieldLabel("ROLE", icon: "tag.fill")
//                                let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
//                                LazyVGrid(columns: cols, spacing: 8) {
//                                    ForEach(roles, id: \.self) { r in
//                                        let isSel = role == r
//                                        Button {
//                                            withAnimation(.easeInOut(duration: 0.15)) {
//                                                role = isSel ? "" : r
//                                            }
//                                        } label: {
//                                            Text(r)
//                                                .font(.system(size: 11, weight: isSel ? .heavy : .medium))
//                                                .foregroundColor(isSel ? .white : Color(hex: "#1A1208")!)
//                                                .frame(maxWidth: .infinity)
//                                                .padding(.vertical, 10)
//                                                .background(
//                                                    RoundedRectangle(cornerRadius: 10)
//                                                        .fill(isSel ? avatarColor : Color.white)
//                                                        .overlay(
//                                                            RoundedRectangle(cornerRadius: 10)
//                                                                .stroke(isSel ? avatarColor : Color(hex: "#E6DDD0")!, lineWidth: 1)
//                                                        )
//                                                )
//                                                .shadow(color: isSel ? avatarColor.opacity(0.25) : .clear, radius: 4, y: 2)
//                                        }
//                                        .buttonStyle(.plain)
//                                        .animation(.easeInOut(duration: 0.15), value: isSel)
//                                    }
//                                }
//                            }
//                            .shake(trigger: shakeTrigger)
//
//                            // ── Send button ───────────────────
//                            Button { sendInvite() } label: {
//                                HStack(spacing: 10) {
//                                    Image(systemName: "paperplane.fill")
//                                        .font(.system(size: 16))
//                                    Text("Send Invitation")
//                                        .font(.system(size: 16, weight: .bold))
//                                }
//                                .foregroundColor(.white)
//                                .frame(maxWidth: .infinity)
//                                .padding(.vertical, 17)
//                                .background(isValid ? avatarColor : Color(hex: "#C5C0B8")!)
//                                .cornerRadius(16)
//                                .shadow(color: isValid ? avatarColor.opacity(0.4) : .clear, radius: 10, y: 4)
//                                .animation(.easeInOut(duration: 0.15), value: isValid)
//                            }
//                            .disabled(!isValid)
//                            .padding(.bottom, 32)
//                        }
//                        .padding(.horizontal, 24)
//                        .padding(.top, 12)
//                    }
//                }
//            }
//            .navigationTitle("Invite Member")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") { dismiss() }
//                        .foregroundColor(Color(hex: "#C8922A")!)
//                }
//            }
//        }
//        .presentationDetents([.large])
//        .presentationDragIndicator(.visible)
//    }
//
//    // MARK: - Sent Confirmation
//    private var sentConfirmation: some View {
//        VStack(spacing: 24) {
//            Spacer()
//            ZStack {
//                Circle().fill(Color(hex: "#EAF7EF")!).frame(width: 110, height: 110)
//                Image(systemName: "checkmark.circle.fill")
//                    .font(.system(size: 54))
//                    .foregroundColor(Color(hex: "#4A9E6B")!)
//            }
//            VStack(spacing: 10) {
//                Text("Invitation Sent!")
//                    .font(.system(size: 24, weight: .black))
//                    .foregroundColor(Color(hex: "#1A1208")!)
//                Text("An invitation email has been opened\nfor \(name) (\(email)).")
//                    .font(.system(size: 14, weight: .medium))
//                    .foregroundColor(Color(hex: "#7A6A55")!)
//                    .multilineTextAlignment(.center)
//
//                // Code reminder
//                VStack(spacing: 6) {
//                    Text("Their code is")
//                        .font(.system(size: 12))
//                        .foregroundColor(Color(hex: "#7A6A55")!)
//                    Text(generatedCode)
//                        .font(.system(size: 30, weight: .black, design: .monospaced))
//                        .foregroundColor(avatarColor)
//                        .kerning(4)
//                    Text("Valid for 7 days")
//                        .font(.system(size: 11))
//                        .foregroundColor(Color(hex: "#7A6A55")!)
//                }
//                .padding(16)
//                .background(Color.white)
//                .cornerRadius(16)
//                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
//                .padding(.top, 8)
//            }
//            Spacer()
//            Button { dismiss() } label: {
//                Text("Done")
//                    .font(.system(size: 16, weight: .bold))
//                    .foregroundColor(.white)
//                    .frame(maxWidth: .infinity)
//                    .padding(.vertical, 17)
//                    .background(Color(hex: "#4A9E6B")!)
//                    .cornerRadius(16)
//            }
//            .padding(.horizontal, 24)
//            .padding(.bottom, 40)
//        }
//    }
//
//    // MARK: - Field builder
//    @ViewBuilder
//    private func inviteField(
//        label: String, icon: String, placeholder: String,
//        text: Binding<String>, field: InviteField,
//        keyboard: UIKeyboardType, autocap: TextInputAutocapitalization
//    ) -> some View {
//        VStack(alignment: .leading, spacing: 6) {
//            fieldLabel(label, icon: icon)
//            TextField(placeholder, text: text)
//                .font(.system(size: 16, weight: .semibold))
//                .foregroundColor(Color(hex: "#1A1208")!)
//                .keyboardType(keyboard)
//                .textInputAutocapitalization(autocap)
//                .autocorrectionDisabled()
//                .focused($focused, equals: field)
//                .padding(14)
//                .background(Color.white)
//                .cornerRadius(12)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12)
//                        .stroke(
//                            focused == field ? avatarColor : Color(hex: "#E6DDD0")!,
//                            lineWidth: focused == field ? 2 : 1
//                        )
//                        .animation(.easeInOut(duration: 0.15), value: focused == field)
//                )
//                .shadow(color: focused == field ? avatarColor.opacity(0.12) : .clear, radius: 6, y: 2)
//        }
//    }
//
//    private func fieldLabel(_ text: String, icon: String) -> some View {
//        HStack(spacing: 5) {
//            Image(systemName: icon)
//                .font(.system(size: 9, weight: .bold))
//                .foregroundColor(Color(hex: "#7A6A55")!)
//            Text(text)
//                .font(.system(size: 9, weight: .heavy))
//                .kerning(1.4)
//                .foregroundColor(Color(hex: "#7A6A55")!)
//        }
//    }
//
//    // MARK: - Send
//    private func sendInvite() {
//        guard isValid else { withAnimation { shakeTrigger += 1 }; return }
//        focused = nil
//
//        let invite = HouseholdInvite(
//            name:           name.trimmingCharacters(in: .whitespaces),
//            email:          email.lowercased().trimmingCharacters(in: .whitespaces),
//            role:           role,
//            avatarColorHex: selectedColor
//        )
//
//        // Persist the invite
//        onSend(invite)
//
//        // Override the code so the saved invite matches what we show
//        // (the invite was created with a generated code already)
//        generatedCode = invite.code
//
//        // Open Mail
//        HouseholdInviteService.shared.sendInviteEmail(
//            invite: invite,
//            senderName: senderName
//        )
//
//        withAnimation(.spring()) { isSent = true }
//    }
//
//    private func isValidEmail(_ email: String) -> Bool {
//        email.contains("@") && email.contains(".") && email.count > 5
//    }
//}
//
//// MARK: - MemberCard (grid card)
//struct MemberCard: View {
//    let member:   HouseholdMember
//    let onDelete: () -> Void
//
//    private var avatarColor: Color {
//        Color(hex: member.avatarColorHex) ?? Color(hex: "#C8922A")!
//    }
//
//    var body: some View {
//        VStack(spacing: 0) {
//            LinearGradient(
//                colors: [avatarColor, avatarColor.opacity(0.7)],
//                startPoint: .leading, endPoint: .trailing
//            )
//            .frame(height: 6)
//
//            VStack(spacing: 12) {
//                ZStack {
//                    Circle().fill(avatarColor.opacity(0.12)).frame(width: 68, height: 68)
//                    Circle().fill(avatarColor).frame(width: 56, height: 56)
//                        .shadow(color: avatarColor.opacity(0.4), radius: 8, y: 4)
//                    Text(member.initials)
//                        .font(.system(size: 20, weight: .black))
//                        .foregroundColor(.white)
//                }
//                .padding(.top, 16)
//
//                Text(member.name)
//                    .font(.system(size: 15, weight: .bold))
//                    .foregroundColor(Color(hex: "#1A1208")!)
//                    .lineLimit(1).minimumScaleFactor(0.8)
//
//                Text(member.role.isEmpty ? "Member" : member.role)
//                    .font(.system(size: 10, weight: .heavy)).kerning(0.4)
//                    .foregroundColor(avatarColor)
//                    .padding(.horizontal, 10).padding(.vertical, 4)
//                    .background(avatarColor.opacity(0.1))
//                    .cornerRadius(20)
//
//                Button { onDelete() } label: {
//                    HStack(spacing: 4) {
//                        Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
//                        Text("Remove").font(.system(size: 11, weight: .semibold))
//                    }
//                    .foregroundColor(Color(hex: "#7A6A55")!.opacity(0.75))
//                    .padding(.horizontal, 10).padding(.vertical, 6)
//                    .background(Color(hex: "#F2EDE5")!)
//                    .cornerRadius(20)
//                }
//                .padding(.bottom, 14)
//            }
//        }
//        .background(Color.white)
//        .cornerRadius(18)
//        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(hex: "#E6DDD0")!, lineWidth: 1))
//        .shadow(color: Color(hex: "#1A1208")!.opacity(0.06), radius: 10, y: 4)
//    }
//}
//
//// MARK: - AddMemberSheet (manual add)
//struct AddMemberSheet: View {
//    @ObservedObject var scheduleVM: ScheduleViewModel
//    @Environment(\.dismiss) var dismiss
//
//    @State private var name          = ""
//    @State private var role          = ""
//    @State private var selectedColor = HouseholdMember.sampleColors[0]
//    @State private var shakeTrigger: CGFloat = 0
//    @FocusState private var nameFocused: Bool
//
//    private let roles = ["Spouse / Partner", "Child", "Parent", "Roommate", "Other"]
//    private var avatarColor: Color { Color(hex: selectedColor) ?? Color(hex: "#C8922A")! }
//
//    var body: some View {
//        NavigationStack {
//            ZStack {
//                Color(hex: "#FAF7F2")!.ignoresSafeArea()
//                ScrollView(showsIndicators: false) {
//                    VStack(spacing: 28) {
//                        // Avatar preview
//                        ZStack {
//                            Circle().fill(avatarColor.opacity(0.1)).frame(width: 130, height: 130)
//                            Circle().fill(avatarColor.opacity(0.18)).frame(width: 106, height: 106)
//                            Circle().fill(avatarColor).frame(width: 90, height: 90)
//                                .shadow(color: avatarColor.opacity(0.45), radius: 14, y: 6)
//                            Text(name.isEmpty ? "?" : String(name.prefix(1)).uppercased())
//                                .font(.system(size: 36, weight: .black)).foregroundColor(.white)
//                        }
//                        .animation(.spring(response: 0.3), value: selectedColor)
//                        .padding(.top, 8)
//
//                        // Color swatches
//                        HStack(spacing: 12) {
//                            ForEach(HouseholdMember.sampleColors, id: \.self) { hex in
//                                let isSelected = selectedColor == hex
//                                Button { withAnimation(.spring(response: 0.2)) { selectedColor = hex } } label: {
//                                    ZStack {
//                                        Circle().fill(Color(hex: hex) ?? .gray).frame(width: 34, height: 34)
//                                            .shadow(color: (Color(hex: hex) ?? .gray).opacity(0.4), radius: 4, y: 2)
//                                        if isSelected {
//                                            Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 34, height: 34)
//                                            Image(systemName: "checkmark").font(.system(size: 10, weight: .black)).foregroundColor(.white)
//                                        }
//                                    }
//                                    .scaleEffect(isSelected ? 1.2 : 1.0)
//                                    .animation(.spring(response: 0.2), value: isSelected)
//                                }
//                                .buttonStyle(.plain)
//                            }
//                        }
//
//                        // Name field
//                        VStack(alignment: .leading, spacing: 6) {
//                            HStack(spacing: 5) {
//                                Image(systemName: "person.fill").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "#7A6A55")!)
//                                Text("FULL NAME").font(.system(size: 9, weight: .heavy)).kerning(1.4).foregroundColor(Color(hex: "#7A6A55")!)
//                            }
//                            TextField("e.g. Sarah Johnson", text: $name)
//                                .font(.system(size: 16, weight: .semibold))
//                                .foregroundColor(Color(hex: "#1A1208")!)
//                                .focused($nameFocused)
//                                .textInputAutocapitalization(.words)
//                                .autocorrectionDisabled()
//                                .padding(14)
//                                .background(Color.white)
//                                .cornerRadius(12)
//                                .overlay(
//                                    RoundedRectangle(cornerRadius: 12)
//                                        .stroke(nameFocused ? avatarColor : Color(hex: "#E6DDD0")!, lineWidth: nameFocused ? 2 : 1)
//                                        .animation(.easeInOut(duration: 0.15), value: nameFocused)
//                                )
//                                .shadow(color: nameFocused ? avatarColor.opacity(0.15) : .clear, radius: 6, y: 2)
//                        }
//                        .shake(trigger: shakeTrigger)
//
//                        // Role chips
//                        VStack(alignment: .leading, spacing: 10) {
//                            HStack(spacing: 5) {
//                                Image(systemName: "tag.fill").font(.system(size: 9, weight: .bold)).foregroundColor(Color(hex: "#7A6A55")!)
//                                Text("ROLE").font(.system(size: 9, weight: .heavy)).kerning(1.4).foregroundColor(Color(hex: "#7A6A55")!)
//                            }
//                            let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
//                            LazyVGrid(columns: cols, spacing: 8) {
//                                ForEach(roles, id: \.self) { r in
//                                    let isSel = role == r
//                                    Button { withAnimation(.easeInOut(duration: 0.15)) { role = isSel ? "" : r } } label: {
//                                        Text(r).font(.system(size: 11, weight: isSel ? .heavy : .medium))
//                                            .foregroundColor(isSel ? .white : Color(hex: "#1A1208")!)
//                                            .frame(maxWidth: .infinity).padding(.vertical, 10)
//                                            .background(
//                                                RoundedRectangle(cornerRadius: 10)
//                                                    .fill(isSel ? avatarColor : Color.white)
//                                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSel ? avatarColor : Color(hex: "#E6DDD0")!, lineWidth: 1))
//                                            )
//                                            .shadow(color: isSel ? avatarColor.opacity(0.25) : .clear, radius: 4, y: 2)
//                                    }
//                                    .buttonStyle(.plain)
//                                    .animation(.easeInOut(duration: 0.15), value: isSel)
//                                }
//                            }
//                        }
//
//                        // Add button
//                        Button { addMember() } label: {
//                            HStack(spacing: 10) {
//                                Image(systemName: "person.badge.plus").font(.system(size: 17))
//                                Text("Add to Household").font(.system(size: 16, weight: .bold))
//                            }
//                            .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 17)
//                            .background(name.isEmpty ? Color(hex: "#C5C0B8")! : avatarColor)
//                            .cornerRadius(16)
//                            .shadow(color: name.isEmpty ? .clear : avatarColor.opacity(0.4), radius: 10, y: 4)
//                            .animation(.easeInOut(duration: 0.15), value: name.isEmpty)
//                        }
//                        .disabled(name.isEmpty)
//                        .padding(.bottom, 32)
//                    }
//                    .padding(.horizontal, 24).padding(.top, 12)
//                }
//            }
//            .navigationTitle("Add Member")
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .cancellationAction) {
//                    Button("Cancel") { dismiss() }.foregroundColor(Color(hex: "#C8922A")!)
//                }
//            }
//        }
//        .presentationDetents([.large])
//        .presentationDragIndicator(.visible)
//    }
//
//    private func addMember() {
//        guard !name.isEmpty else { withAnimation { shakeTrigger += 1 }; return }
//        scheduleVM.addMember(HouseholdMember(
//            name: name.trimmingCharacters(in: .whitespaces),
//            role: role, avatarColorHex: selectedColor
//        ))
//        dismiss()
//    }
//}
//
//// MARK: - MemberRow (compatibility)
//struct MemberRow: View {
//    let member: HouseholdMember
//    var body: some View {
//        HStack(spacing: 14) {
//            ZStack {
//                Circle().fill(Color(hex: member.avatarColorHex) ?? Color(hex: "#C8922A")!).frame(width: 44, height: 44)
//                Text(member.initials).font(.system(size: 16, weight: .bold)).foregroundColor(.white)
//            }
//            VStack(alignment: .leading, spacing: 3) {
//                Text(member.name).font(.subheadline).bold().foregroundColor(Color(hex: "#1A1208")!)
//                Text(member.role.isEmpty ? "Member" : member.role).font(.caption).foregroundColor(Color(hex: "#7A6A55")!)
//            }
//            Spacer()
//        }
//        .padding(.vertical, 4)
//    }
//}
//
//#Preview {
//    HouseholdMembersView().environmentObject(AuthViewModel())
//}

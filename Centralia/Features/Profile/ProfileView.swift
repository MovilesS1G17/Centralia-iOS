import SwiftUI
import UIKit

struct ProfileView: View {
    private enum Sheet: String, Identifiable {
        case editProfile
        case changePassword
        case notificationPreferences
        case exportLibrary

        var id: String { rawValue }
    }

    @State private var viewModel: ProfileViewModel
    @State private var activeSheet: Sheet?
    @State private var showsSignOutConfirmation = false
    @State private var showsPasswordConfirmation = false
    @State private var signOutFailure: String?

    private let userChanged: (AuthenticatedUser) -> Void
    private let signedOut: () -> Void

    init(
        authenticatedUser: AuthenticatedUser,
        userRepository: any UserRepository,
        videoRepository: any VideoItemRepository,
        folderRepository: any FolderRepository,
        exportService: any LibraryExportService,
        authenticationRepository: any AuthenticationRepository,
        userChanged: @escaping (AuthenticatedUser) -> Void,
        signedOut: @escaping () -> Void
    ) {
        _viewModel = State(
            initialValue: ProfileViewModel(
                authenticatedUser: authenticatedUser,
                userRepository: userRepository,
                videoRepository: videoRepository,
                folderRepository: folderRepository,
                exportService: exportService,
                authenticationRepository: authenticationRepository
            )
        )
        self.userChanged = userChanged
        self.signedOut = signedOut
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: CentraliaTheme.Spacing.large) {
                    Text("Profile")
                        .font(CentraliaTheme.Typography.display)
                        .accessibilityAddTraits(.isHeader)

                    content
                }
                .padding(.horizontal, CentraliaTheme.Spacing.medium)
                .padding(.top, CentraliaTheme.Spacing.medium)
                .padding(.bottom, CentraliaTheme.Spacing.xLarge)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color.centraliaCanvas.ignoresSafeArea())
            .foregroundStyle(Color.centraliaInk)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await viewModel.load() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editProfile:
                if let profile = viewModel.profile {
                    EditProfileSheet(
                        profile: profile,
                        isSaving: viewModel.isUpdatingProfile
                    ) { name, email in
                        guard let user = await viewModel.updateProfile(
                            displayName: name,
                            email: email
                        ) else {
                            return false
                        }
                        userChanged(user)
                        return true
                    }
                }

            case .changePassword:
                ChangePasswordSheet(
                    isSaving: viewModel.isChangingPassword,
                    changePassword: viewModel.changePassword,
                    completed: { showsPasswordConfirmation = true }
                )

            case .notificationPreferences:
                NotificationPreferencesSheet(viewModel: viewModel)

            case .exportLibrary:
                ExportLibrarySheet(
                    statistics: viewModel.statistics,
                    isExporting: viewModel.isExporting,
                    prepareExport: viewModel.prepareExport
                )
            }
        }
        .confirmationDialog(
            "Sign out of Centralia?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    if await viewModel.signOut() {
                        signedOut()
                    } else {
                        signOutFailure = viewModel.failureMessage
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll need to sign in again to access your library.")
        }
        .alert("Password Updated", isPresented: $showsPasswordConfirmation) {
            Button("OK") {}
        } message: {
            Text("Your Centralia password has been changed.")
        }
        .alert(
            "Couldn’t Sign Out",
            isPresented: Binding(
                get: { signOutFailure != nil },
                set: { if !$0 { signOutFailure = nil } }
            )
        ) {
            Button("OK") { signOutFailure = nil }
        } message: {
            Text(signOutFailure ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading profile…")
                .frame(maxWidth: .infinity, minHeight: 520)

        case let .failed(message):
            ContentUnavailableView {
                Label("Profile unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await viewModel.retry() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.centraliaInk)
            }
            .frame(maxWidth: .infinity, minHeight: 520)

        case .loaded:
            if let profile = viewModel.profile {
                identityCard(profile)
                accountActions
                storageCard
                librarySummary
                platformSummary
                signOutButton
            }
        }
    }

    private func identityCard(_ profile: UserProfile) -> some View {
        HStack(spacing: CentraliaTheme.Spacing.medium) {
            Text(profile.initials)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.centraliaSurface)
                .frame(width: 76, height: 76)
                .background(Color.centraliaInk, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName)
                    .font(CentraliaTheme.Typography.sectionTitle)
                    .lineLimit(2)

                Text(profile.email)
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
                    .textSelection(.enabled)

                Text(profile.membershipStatus.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.centraliaSoftSurface, in: Capsule())
            }

            Spacer(minLength: 0)
        }
        .padding(CentraliaTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profileIdentity")
    }

    private var accountActions: some View {
        VStack(spacing: 0) {
            ProfileActionRow(title: "Edit Profile") {
                activeSheet = .editProfile
            }
            Divider().padding(.horizontal, CentraliaTheme.Spacing.medium)
            ProfileActionRow(title: "Change Password") {
                activeSheet = .changePassword
            }
            Divider().padding(.horizontal, CentraliaTheme.Spacing.medium)
            ProfileActionRow(title: "Notification Preferences") {
                activeSheet = .notificationPreferences
            }
        }
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: CentraliaTheme.Spacing.medium) {
            Text("STORAGE & DATA")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.centraliaSecondaryText)

            HStack(alignment: .firstTextBaseline) {
                Text("Storage Used")
                    .font(.headline)
                Spacer()
                Text(viewModel.storageUsage.summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.centraliaSecondaryText)
            }

            ProgressView(value: viewModel.storageUsage.fractionUsed)
                .tint(Color.centraliaInk)
                .accessibilityLabel("Storage used")
                .accessibilityValue(viewModel.storageUsage.summary)

            Divider()

            ProfileActionRow(title: "Export Library Data", hasHorizontalPadding: false) {
                activeSheet = .exportLibrary
            }
        }
        .padding(CentraliaTheme.Spacing.medium)
        .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.centraliaDivider, lineWidth: 1)
        }
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your library")
                .font(CentraliaTheme.Typography.sectionTitle)

            HStack(spacing: 0) {
                ProfileStat(value: viewModel.statistics.savedCount, label: "Saved")
                ProfileStatDivider()
                ProfileStat(value: viewModel.statistics.folderCount, label: "Folders")
                ProfileStatDivider()
                ProfileStat(value: viewModel.statistics.unorganizedCount, label: "To organize")
            }
            .padding(.vertical, CentraliaTheme.Spacing.medium)
            .background(Color.centraliaInk, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var platformSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved by platform")
                .font(CentraliaTheme.Typography.sectionTitle)

            HStack(spacing: CentraliaTheme.Spacing.medium) {
                PlatformStat(
                    color: .centraliaInk,
                    title: "TikTok",
                    value: viewModel.statistics.count(for: .tiktok)
                )
                PlatformStat(
                    color: .centraliaVideoLavender,
                    title: "Reels",
                    value: viewModel.statistics.count(for: .instagramReel)
                )
                PlatformStat(
                    color: .centraliaVideoClay,
                    title: "Shorts",
                    value: viewModel.statistics.count(for: .youtubeShort)
                )
            }
            .padding(CentraliaTheme.Spacing.medium)
            .frame(maxWidth: .infinity)
            .background(Color.centraliaSurface, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.centraliaDivider, lineWidth: 1)
            }
        }
    }

    private var signOutButton: some View {
        CentraliaPrimaryButton(
            title: "Sign Out",
            isLoading: viewModel.isSigningOut,
            action: { showsSignOutConfirmation = true }
        )
        .accessibilityIdentifier("profileSignOut")
    }
}

private struct ProfileActionRow: View {
    let title: String
    var hasHorizontalPadding = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.centraliaSecondaryText)
            }
            .foregroundStyle(Color.centraliaInk)
            .padding(.horizontal, hasHorizontalPadding ? CentraliaTheme.Spacing.medium : 0)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(CentraliaPressStyle())
        .accessibilityIdentifier("profileAction.\(title)")
    }
}

private struct ProfileStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value, format: .number)
                .font(.title.weight(.bold))
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.centraliaSurface.opacity(0.82))
        }
        .foregroundStyle(Color.centraliaSurface)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.centraliaSurface.opacity(0.24))
            .frame(width: 1, height: 46)
            .accessibilityHidden(true)
    }
}

private struct PlatformStat: View {
    let color: Color
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 2)
            Text(value, format: .number)
                .font(.subheadline.weight(.bold))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile
    let isSaving: Bool
    let save: (String, String) async -> Bool

    @State private var displayName: String
    @State private var email: String
    @State private var nameError: String?
    @State private var emailError: String?
    @State private var failureMessage: String?

    init(
        profile: UserProfile,
        isSaving: Bool,
        save: @escaping (String, String) async -> Bool
    ) {
        self.profile = profile
        self.isSaving = isSaving
        self.save = save
        _displayName = State(initialValue: profile.displayName)
        _email = State(initialValue: profile.email)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal information") {
                    TextField("Name", text: $displayName)
                        .textContentType(.name)
                    if let nameError {
                        Text(nameError).foregroundStyle(.red)
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let emailError {
                        Text(emailError).foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Changing your email may require verification when the live API is connected.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        submit()
                    }
                    .disabled(isSaving)
                }
            }
            .alert(
                "Couldn’t Update Profile",
                isPresented: Binding(
                    get: { failureMessage != nil },
                    set: { if !$0 { failureMessage = nil } }
                )
            ) {
                Button("OK") { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = trimmedName.isEmpty ? "Enter your name." : nil
        emailError = AuthenticationValidation.emailError(for: email)
        guard nameError == nil, emailError == nil else { return }

        Task {
            if await save(trimmedName, email) {
                dismiss()
            } else {
                failureMessage = "Your changes could not be saved. Please try again."
            }
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isSaving: Bool
    let changePassword: (String, String) async -> Bool
    let completed: () -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var currentPasswordError: String?
    @State private var newPasswordError: String?
    @State private var confirmationError: String?
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Current password") {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                    if let currentPasswordError {
                        Text(currentPasswordError).foregroundStyle(.red)
                    }
                }

                Section("New password") {
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                    if let newPasswordError {
                        Text(newPasswordError).foregroundStyle(.red)
                    }

                    SecureField("Confirm new password", text: $confirmation)
                        .textContentType(.newPassword)
                    if let confirmationError {
                        Text(confirmationError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") { submit() }
                        .disabled(isSaving)
                }
            }
            .alert(
                "Couldn’t Change Password",
                isPresented: Binding(
                    get: { failureMessage != nil },
                    set: { if !$0 { failureMessage = nil } }
                )
            ) {
                Button("OK") { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.large])
    }

    private func submit() {
        currentPasswordError = currentPassword.isEmpty ? "Enter your current password." : nil
        newPasswordError = AuthenticationValidation.passwordError(for: newPassword)
        confirmationError = newPassword == confirmation ? nil : "Passwords do not match."
        guard currentPasswordError == nil,
              newPasswordError == nil,
              confirmationError == nil else {
            return
        }

        Task {
            if await changePassword(currentPassword, newPassword) {
                dismiss()
                completed()
            } else {
                failureMessage = "Your password could not be changed. Check your current password and try again."
            }
        }
    }
}

private struct NotificationPreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ProfileViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preferenceToggle(
                        "Organization reminders",
                        detail: "Remind me when saved shorts still need a folder.",
                        keyPath: \.organizationReminders
                    )
                    preferenceToggle(
                        "Weekly library summary",
                        detail: "Receive a weekly overview of saved content.",
                        keyPath: \.weeklyLibrarySummary
                    )
                    preferenceToggle(
                        "Product updates",
                        detail: "Hear about new Centralia features.",
                        keyPath: \.productUpdates
                    )
                } footer: {
                    Text("Changes are saved automatically and will sync with your account.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Couldn’t Save Preferences",
                isPresented: Binding(
                    get: { viewModel.failureMessage != nil },
                    set: { if !$0 { viewModel.dismissFailure() } }
                )
            ) {
                Button("OK") { viewModel.dismissFailure() }
            } message: {
                Text(viewModel.failureMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func preferenceToggle(
        _ title: String,
        detail: String,
        keyPath: WritableKeyPath<NotificationPreferences, Bool>
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { viewModel.notificationPreferences[keyPath: keyPath] },
                set: { newValue in
                    var preferences = viewModel.notificationPreferences
                    preferences[keyPath: keyPath] = newValue
                    Task { await viewModel.updateNotificationPreferences(preferences) }
                }
            )
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(viewModel.isSavingPreferences)
    }
}

private struct ExportLibrarySheet: View {
    private struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @Environment(\.dismiss) private var dismiss

    let statistics: LibraryStatistics
    let isExporting: Bool
    let prepareExport: () async -> URL?

    @State private var exportedFile: ExportedFile?
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Included in your export") {
                    Label("\(statistics.savedCount) saved shorts", systemImage: "play.rectangle")
                    Label("\(statistics.folderCount) folders", systemImage: "folder")
                    Label("Tags, notes, and source links", systemImage: "tag")
                    Label("Profile and notification preferences", systemImage: "person.text.rectangle")
                }

                Section("Format") {
                    LabeledContent("File type", value: "JSON")
                    Text("The export is human-readable and can also be imported by another service.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            guard let url = await prepareExport() else {
                                failureMessage = "Your library export could not be prepared."
                                return
                            }
                            exportedFile = ExportedFile(url: url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Library Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
            .sheet(item: $exportedFile) { file in
                ActivityShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .alert(
                "Export Unavailable",
                isPresented: Binding(
                    get: { failureMessage != nil },
                    set: { if !$0 { failureMessage = nil } }
                )
            ) {
                Button("OK") { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "Please try again.")
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

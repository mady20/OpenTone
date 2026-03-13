import Foundation
internal import PostgREST
import Supabase

final class UserDataModel {

    static let shared = UserDataModel()

    // In-memory cache
    private(set) var allUsers: [User] = []
    private var currentUser: User?

    /// Key for persisting the current user's UUID across launches.
    private let currentUserIDKey = "currentUserID"

    private(set) var isLoaded = false

    private init() {
        // Kick off an async load — callers should observe `allUsers` after this completes.
        Task { @MainActor in
            await restoreCurrentUser()
            await loadAllUsersFromSupabase()
            self.isLoaded = true
            SessionManager.shared.refreshSession()
            NotificationCenter.default.post(name: NSNotification.Name("UserDataModelLoaded"), object: nil)
        }
    }

    // MARK: - Current User

    func getCurrentUser() -> User? {
        currentUser
    }

    func setCurrentUser(_ user: User) {
        currentUser = user
        UserDefaults.standard.set(user.id.uuidString, forKey: currentUserIDKey)
    }

    func updateCurrentUser(_ updatedUser: User) {
        guard currentUser?.id == updatedUser.id else { return }
        currentUser = updatedUser

        // Update in-memory cache
        if let index = allUsers.firstIndex(where: { $0.id == updatedUser.id }) {
            allUsers[index] = updatedUser
        }

        // Persist to Supabase
        Task {
            await updateUserInSupabase(updatedUser)
        }
    }

    func deleteCurrentUser() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: currentUserIDKey)
    }

    // MARK: - Registration & Auth

    func registerUser(_ user: User) -> Bool {
        guard !allUsers.contains(where: { $0.email == user.email }) else {
            return false
        }

        allUsers.append(user)
        setCurrentUser(user)

        Task {
            await insertUserInSupabase(user)
        }
        return true
    }

    /// Registers credentials in Supabase Auth, then upserts a profile row in `users`.
    func registerWithSupabaseAuth(name: String, email: String, password: String) async -> User? {
        do {
            try await SupabaseAuth.signUp(email: email, password: password)
            let authUser = try await SupabaseAuth.signIn(email: email, password: password)
            var user = User(
                name: name,
                email: email,
                password: "",
                country: nil,
                avatar: "pp1"
            )
            user.setID(authUser.id)

            await insertUserInSupabase(user)
            await MainActor.run {
                self.setCurrentUser(user)
                if !self.allUsers.contains(where: { $0.id == user.id }) {
                    self.allUsers.append(user)
                }
            }
            return user
        } catch {
            print("❌ Supabase signup error: \(error.localizedDescription)")
            return nil
        }
    }

    func authenticate(email: String, password: String) async -> User? {
        do {
            let authUser = try await SupabaseAuth.signIn(email: email, password: password)
            let user = try await fetchOrCreateProfile(
                userID: authUser.id,
                email: authUser.email ?? email,
                suggestedName: nil
            )

            await MainActor.run {
                self.setCurrentUser(user)
                if !self.allUsers.contains(where: { $0.id == user.id }) {
                    self.allUsers.append(user)
                }
            }
            return user
        } catch {
            print("❌ Supabase login error: \(error.localizedDescription)")
            return nil
        }
    }

    func getUser(by id: UUID) -> User? {
        allUsers.first { $0.id == id }
    }

    func getSampleUserForQuickSignIn() -> User? {
        allUsers.first { user in
            user.confidenceLevel != nil &&
            user.englishLevel != nil &&
            user.interests != nil &&
            !user.interests!.isEmpty
        }
    }

    // MARK: - Field Updaters

    func updateLastSeen() {
        guard var user = currentUser else { return }
        user.lastSeen = Date()
        updateCurrentUser(user)
    }



    func addRoleplayID(_ id: UUID) {
        SessionManager.shared.refreshSession()
    }

    func addJamSessionID(_ id: UUID) {
        SessionManager.shared.refreshSession()
    }

    func addFriendID(_ id: UUID) {
        guard var user = currentUser else { return }
        user.friendsIDs.append(id)
        updateCurrentUser(user)
    }

    func removeFriendID(_ id: UUID) {
        guard var user = currentUser else { return }
        user.friendsIDs.removeAll { $0 == id }
        updateCurrentUser(user)
    }

    // MARK: - Supabase Operations

    private func loadAllUsersFromSupabase() async {
        guard await SupabaseAuth.hasActiveSession() else {
            await MainActor.run {
                self.allUsers = []
            }
            return
        }

        guard let authUserID = await SupabaseAuth.currentUserID() else {
            await MainActor.run {
                self.allUsers = []
            }
            return
        }

        do {
            let rows: [UserRow] = try await supabase
                .from(SupabaseTable.users)
                .select()
                .eq("id", value: authUserID.uuidString)
                .execute()
                .value
            let users = rows.map { $0.toUser() }
            await MainActor.run {
                self.allUsers = users
            }
        } catch {
            print("❌ Failed to load users from Supabase: \(error.localizedDescription)")
            await MainActor.run {
                self.allUsers = []
            }
        }
    }

    private func restoreCurrentUser() async {
        guard await SupabaseAuth.hasActiveSession() else {
            await MainActor.run {
                self.currentUser = nil
                UserDefaults.standard.removeObject(forKey: self.currentUserIDKey)
            }
            return
        }

        do {
            let sessionUser = try await SupabaseAuth.sessionUser()
            if let cached = allUsers.first(where: { $0.id == sessionUser.id }) {
                await MainActor.run {
                    self.currentUser = cached
                    UserDefaults.standard.set(cached.id.uuidString, forKey: self.currentUserIDKey)
                }
                return
            }

            let user = try await fetchOrCreateProfile(
                userID: sessionUser.id,
                email: sessionUser.email,
                suggestedName: nil
            )
            await MainActor.run {
                self.currentUser = user
                UserDefaults.standard.set(user.id.uuidString, forKey: self.currentUserIDKey)
                if !self.allUsers.contains(where: { $0.id == user.id }) {
                    self.allUsers.append(user)
                }
            }
        } catch {
            print("❌ Failed to restore Supabase session user: \(error.localizedDescription)")
            await MainActor.run {
                self.currentUser = nil
                UserDefaults.standard.removeObject(forKey: self.currentUserIDKey)
            }
        }
    }

    /// Test hook: exercises the same restore logic used on app launch.
    func restoreCurrentUserFromSessionForTesting() async {
        await restoreCurrentUser()
    }

    func cacheUserForTesting(_ user: User) {
        if let index = allUsers.firstIndex(where: { $0.id == user.id }) {
            allUsers[index] = user
        } else {
            allUsers.append(user)
        }
    }

    private func fetchOrCreateProfile(userID: UUID, email: String?, suggestedName: String?) async throws -> User {
        let rows: [UserRow] = try await supabase
            .from(SupabaseTable.users)
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value

        if let row = rows.first {
            return row.toUser()
        }

        let defaultName: String
        if let suggestedName, !suggestedName.isEmpty {
            defaultName = suggestedName
        } else if let email {
            defaultName = email.split(separator: "@").first.map(String.init) ?? "OpenTone User"
        } else {
            defaultName = "OpenTone User"
        }

        var user = User(
            name: defaultName,
            email: email ?? "",
            password: "",
            country: nil,
            avatar: "pp1"
        )
        user.setID(userID)
        await insertUserInSupabase(user)
        return user
    }

    private func insertUserInSupabase(_ user: User) async {
        do {
            let row = UserRow(from: user)
            try await supabase
                .from(SupabaseTable.users)
                .insert(row)
                .execute()
        } catch {
            print("❌ Failed to insert user: \(error.localizedDescription)")
        }
    }

    private func updateUserInSupabase(_ user: User) async {
        do {
            let row = UserRow(from: user)
            try await supabase
                .from(SupabaseTable.users)
                .update(row)
                .eq("id", value: user.id.uuidString)
                .execute()
        } catch {
            print("❌ Failed to update user: \(error.localizedDescription)")
        }
    }

    private func loadSampleUsers() -> [User] {
        [
            User(
                name: "Madhav Sharma",
                email: "madhav@opentone.com",
                password: "Madhav@123",
                country: Country(name: "India", code: "IN"),
                age: 20,
                gender: .male,
                bio: "Learning to communicate every day and loving the progress. Passionate about public speaking and making new connections.",
                englishLevel: .beginner,
                confidenceLevel: ConfidenceOption(title: "Very Nervous", emoji: "🥺"),
                interests: [
                    InterestItem(title: "Public Speaking", symbol: "🎤"),
                    InterestItem(title: "Travel", symbol: "✈️"),
                    InterestItem(title: "Technology", symbol: "💻"),
                    InterestItem(title: "Movies", symbol: "🎬"),
                ],
                currentPlan: .free,
                avatar: "pp1",
                streak: Streak(commitment: 10, currentCount: 5, longestCount: 8, lastActiveDate: Date()),
                lastSeen: Date().addingTimeInterval(-120),
                roleplayIDs: [],
                jamSessionIDs: [],
                friends: [],
                goal: 10
            ),
            User(
                name: "Harshdeep Singh",
                email: "harsh@opentone.com",
                password: "Harsh@123",
                country: Country(name: "India", code: "IN"),
                age: 19,
                gender: .male,
                bio: "On a journey to improve my Communication Skills. Love meeting people and exploring new cultures.",
                englishLevel: .intermediate,
                confidenceLevel: ConfidenceOption(title: "Somewhat Confident", emoji: "😊"),
                interests: [
                    InterestItem(title: "Casual Conversation", symbol: "💬"),
                    InterestItem(title: "Interview Practice", symbol: "🧑‍💼"),
                    InterestItem(title: "Music", symbol: "🎵"),
                ],
                currentPlan: .free,
                avatar: "pp2",
                streak: Streak(commitment: 15, currentCount: 3, longestCount: 5, lastActiveDate: Date().addingTimeInterval(-86400)),
                lastSeen: Date(),
                roleplayIDs: [],
                jamSessionIDs: [],
                friends: [],
                goal: 15
            )
        ]
    }
}

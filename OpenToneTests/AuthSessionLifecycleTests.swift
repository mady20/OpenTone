import XCTest
@testable import OpenTone

@MainActor
final class AuthSessionLifecycleTests: XCTestCase {

    private let currentUserIDKey = "currentUserID"
    private let lastWpmDeltaKey = "opentone.lastWpmDelta"

    override func setUp() {
        super.setUp()
        resetAuthOverrides()

        UserDefaults.standard.removeObject(forKey: currentUserIDKey)
        UserDefaults.standard.removeObject(forKey: lastWpmDeltaKey)

        // Initialize singletons under a deterministic no-session test state.
        _ = UserDataModel.shared
        _ = SessionManager.shared

        UserDataModel.shared.deleteCurrentUser()
        SessionManager.shared.refreshSession()
    }

    override func tearDown() {
        resetAuthOverrides()
        UserDataModel.shared.deleteCurrentUser()
        SessionManager.shared.refreshSession()
        UserDefaults.standard.removeObject(forKey: currentUserIDKey)
        UserDefaults.standard.removeObject(forKey: lastWpmDeltaKey)
        super.tearDown()
    }

    func testLoginPersistsCurrentUserID() {
        let user = makeUser(name: "Auth Test", email: "auth@test.local")

        SessionManager.shared.login(user: user)

        XCTAssertTrue(SessionManager.shared.isLoggedIn)
        XCTAssertEqual(SessionManager.shared.currentUser?.id, user.id)
        XCTAssertEqual(UserDefaults.standard.string(forKey: currentUserIDKey), user.id.uuidString)
    }

    func testSessionRestoreUsesStoredSupabaseSessionUser() async {
        var user = makeUser(name: "Restore Test", email: "restore@test.local")
        let fixedID = UUID()
        user.setID(fixedID)

        UserDataModel.shared.cacheUserForTesting(user)
        UserDataModel.shared.deleteCurrentUser()

        SupabaseAuth.hasActiveSessionOverride = { true }
        SupabaseAuth.sessionUserOverride = {
            (id: fixedID, email: user.email)
        }

        await UserDataModel.shared.restoreCurrentUserFromSessionForTesting()

        XCTAssertEqual(UserDataModel.shared.getCurrentUser()?.id, fixedID)
        XCTAssertEqual(UserDefaults.standard.string(forKey: currentUserIDKey), fixedID.uuidString)
    }

    func testAuthenticatedAPIAccessReflectsSessionTokenPresence() async {
        SupabaseAuth.accessTokenOverride = { "test-access-token" }
        XCTAssertTrue(await SessionManager.shared.hasAuthenticatedAPIAccess())

        SupabaseAuth.accessTokenOverride = { nil }
        XCTAssertFalse(await SessionManager.shared.hasAuthenticatedAPIAccess())
    }

    func testLogoutClearsSessionStateAndCachedKeys() async {
        var signOutCalled = false
        SupabaseAuth.signOutOverride = {
            signOutCalled = true
        }

        let user = makeUser(name: "Logout Test", email: "logout@test.local")
        SessionManager.shared.login(user: user)
        UserDefaults.standard.set(1.5, forKey: lastWpmDeltaKey)

        await SessionManager.shared.logoutAsync()

        XCTAssertTrue(signOutCalled)
        XCTAssertFalse(SessionManager.shared.isLoggedIn)
        XCTAssertNil(SessionManager.shared.currentUser)
        XCTAssertNil(UserDefaults.standard.object(forKey: currentUserIDKey))
        XCTAssertNil(UserDefaults.standard.object(forKey: lastWpmDeltaKey))
    }

    private func makeUser(name: String, email: String) -> User {
        User(
            name: name,
            email: email,
            password: "",
            country: nil,
            avatar: "pp1"
        )
    }

    private func resetAuthOverrides() {
        SupabaseAuth.signInOverride = nil
        SupabaseAuth.signUpOverride = nil
        SupabaseAuth.signOutOverride = nil
        SupabaseAuth.sessionUserOverride = nil
        SupabaseAuth.hasActiveSessionOverride = { false }
        SupabaseAuth.accessTokenOverride = nil
        SupabaseAuth.updatePasswordOverride = nil
    }
}

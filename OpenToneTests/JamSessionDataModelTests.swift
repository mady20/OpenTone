import XCTest
@testable import OpenTone

@MainActor
final class JamSessionDataModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let testUser = User(
            name: "Jam Test User",
            email: "jam.tests@opentone.local",
            password: "test123",
            country: Country(name: "India", code: "IN")
        )
        UserDataModel.shared.setCurrentUser(testUser)
        JamSessionDataModel.shared.cancelJamSession()
        JamSessionDataModel.shared.deleteSavedSession()
    }

    override func tearDown() {
        JamSessionDataModel.shared.cancelJamSession()
        JamSessionDataModel.shared.deleteSavedSession()
        super.tearDown()
    }

    func testStartNewSessionUsesLocalTopicCatalog() async {
        let session = await withCheckedContinuation { continuation in
            JamSessionDataModel.shared.startNewSession { session in
                continuation.resume(returning: session)
            }
        }

        XCTAssertNotNil(session)
        guard let session else { return }

        XCTAssertTrue(JamSession.availableTopics.contains(session.topic))
        XCTAssertFalse(session.suggestions.isEmpty)
        XCTAssertEqual(session.phase, .preparing)
        XCTAssertEqual(session.secondsLeft, 30)
    }

    func testRegenerateTopicChangesTopicAndResetsPrepTimer() async {
        let firstSession = await withCheckedContinuation { continuation in
            JamSessionDataModel.shared.startNewSession { session in
                continuation.resume(returning: session)
            }
        }

        XCTAssertNotNil(firstSession)
        let oldTopic = firstSession?.topic

        let regenerated = await withCheckedContinuation { continuation in
            JamSessionDataModel.shared.regenerateTopicForActiveSession { session in
                continuation.resume(returning: session)
            }
        }

        XCTAssertNotNil(regenerated)
        guard let regenerated else { return }

        XCTAssertNotEqual(regenerated.topic, oldTopic)
        XCTAssertTrue(JamSession.availableTopics.contains(regenerated.topic))
        XCTAssertFalse(regenerated.suggestions.isEmpty)
        XCTAssertEqual(regenerated.secondsLeft, 30)
        XCTAssertNotNil(regenerated.startedPrepAt)
    }
}

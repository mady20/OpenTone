import Foundation

/// Domain model for a 1-on-1 AI Call record.
/// Maps to the `call_records` table in Supabase.
struct CallRecord: Identifiable, Codable, Equatable {

    private(set) var id: UUID

    /// Override the auto-generated UUID (used when loading from Supabase).
    mutating func setID(_ newID: UUID) { id = newID }

    let userId: UUID

    /// The AI participant's UUID (a fixed constant since there's only one AI).
    let participantId: UUID

    /// Display name of the AI participant shown in call history.
    var participantName: String?

    /// Avatar URL or asset name for the AI participant.
    var participantAvatarUrl: String?

    /// Short bio of the AI participant.
    var participantBio: String?

    /// Interests of the AI participant (stored as JSONB in Supabase).
    var participantInterests: [String]?

    /// When the call started.
    let callDate: Date

    /// Call duration in seconds.
    var duration: Double

    /// User's status at the end of the call.
    var userStatus: UserStatus

    init(
        userId: UUID,
        participantId: UUID = CallRecord.aiParticipantId,
        participantName: String? = "AI Coach",
        participantAvatarUrl: String? = nil,
        participantBio: String? = "Your personal English speaking coach",
        participantInterests: [String]? = nil,
        callDate: Date = Date(),
        duration: Double = 0,
        userStatus: UserStatus = .online
    ) {
        self.id = UUID()
        self.userId = userId
        self.participantId = participantId
        self.participantName = participantName
        self.participantAvatarUrl = participantAvatarUrl
        self.participantBio = participantBio
        self.participantInterests = participantInterests
        self.callDate = callDate
        self.duration = duration
        self.userStatus = userStatus
    }

    static func == (lhs: CallRecord, rhs: CallRecord) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Constants

    /// A fixed UUID representing the AI participant in all calls.
    static let aiParticipantId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

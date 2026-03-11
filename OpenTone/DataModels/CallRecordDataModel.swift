import Foundation
internal import PostgREST
import Supabase

@MainActor
class CallRecordDataModel {

    static let shared = CallRecordDataModel()

    static let dataLoadedNotification = Notification.Name("CallRecordDataModel.dataLoaded")

    private var callRecords: [CallRecord] = []

    private init() {
        Task {
            await loadCallRecords()
        }
    }

    /// Clears in-memory data and reloads for the current user.
    func reloadForCurrentUser() {
        callRecords = []
        Task {
            await loadCallRecords()
        }
    }

    // MARK: - Read

    func getAllCallRecords() -> [CallRecord] {
        callRecords.sorted { $0.callDate > $1.callDate }
    }

    func getCallRecord(by id: UUID) -> CallRecord? {
        callRecords.first { $0.id == id }
    }

    /// Total number of AI calls the user has made.
    func totalCallCount() -> Int {
        callRecords.count
    }

    /// Total call duration in seconds.
    func totalCallDuration() -> Double {
        callRecords.reduce(0) { $0 + $1.duration }
    }

    // MARK: - Write

    /// Save a new call record after an AI Call session ends.
    func addCallRecord(_ record: CallRecord) {
        callRecords.append(record)

        Task {
            await insertCallRecordInSupabase(record)
        }
    }

    /// Convenience: create and save a call record from the AI Call flow.
    func logCall(
        userId: UUID,
        duration: Double,
        participantName: String = "AI Coach",
        participantBio: String = "Your personal English speaking coach"
    ) {
        let record = CallRecord(
            userId: userId,
            participantName: participantName,
            participantBio: participantBio,
            callDate: Date(),
            duration: duration,
            userStatus: .online
        )
        addCallRecord(record)
    }

    func deleteCallRecord(by id: UUID) {
        callRecords.removeAll { $0.id == id }
        Task {
            await deleteCallRecordFromSupabase(id)
        }
    }

    // MARK: - Supabase Operations

    private func loadCallRecords() async {
        guard let userId = UserDataModel.shared.getCurrentUser()?.id else {
            callRecords = []
            return
        }

        do {
            let rows: [CallRecordRow] = try await supabase
                .from(SupabaseTable.callRecords)
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("call_date", ascending: false)
                .execute()
                .value
            callRecords = rows.map { $0.toCallRecord() }

            NotificationCenter.default.post(name: CallRecordDataModel.dataLoadedNotification, object: nil)
        } catch {
            print("❌ Failed to load call records: \(error.localizedDescription)")
            callRecords = []
            NotificationCenter.default.post(name: CallRecordDataModel.dataLoadedNotification, object: nil)
        }
    }

    private func insertCallRecordInSupabase(_ record: CallRecord) async {
        do {
            let row = CallRecordRow(from: record)
            try await supabase
                .from(SupabaseTable.callRecords)
                .insert(row)
                .execute()
        } catch {
            print("❌ Failed to insert call record: \(error.localizedDescription)")
        }
    }

    private func deleteCallRecordFromSupabase(_ id: UUID) async {
        do {
            try await supabase
                .from(SupabaseTable.callRecords)
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            print("❌ Failed to delete call record: \(error.localizedDescription)")
        }
    }
}

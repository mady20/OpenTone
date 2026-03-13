import Foundation
internal import PostgREST
import Supabase

@MainActor
class HistoryDataModel {

    static let shared = HistoryDataModel()
    
    static let historyDataLoadedNotification = Notification.Name("HistoryDataModel.historyDataLoaded")

    private var activities: [Activity] = []
    private(set) var isLoaded = false

    private init() {
        Task {
            await loadHistory()
        }
    }

    /// Clears in-memory data and reloads for the current user.
    func reloadForCurrentUser() {
        activities = []
        isLoaded = false
        Task {
            await loadHistory()
        }
    }

    // MARK: - Read

    func getActivities(for date: Date) -> [Activity] {
        let calendar = Calendar.current
        return activities.filter { activity in
            calendar.isDate(activity.date, inSameDayAs: date)
        }
    }

    func searchHistory(by type: ActivityType) -> [Activity] {
        return activities.filter { $0.type == type }
    }

    func getAllActivities() -> [Activity] {
        return activities.sorted { $0.date > $1.date }
    }

    // MARK: - Write

    func addActivity(_ activity: Activity) {
        activities.append(activity)

        Task {
            await insertActivityInSupabase(activity)
        }
    }

    func logActivity(
        type: ActivityType,
        title: String,
        topic: String,
        duration: Int,
        imageURL: String,
        xpEarned: Int = 5,
        isCompleted: Bool = true,
        scenarioId: UUID? = nil,
        feedback: SessionFeedback? = nil
    ) {
        let activity = Activity(
            type: type,
            date: Date(),
            topic: topic,
            duration: duration,
            xpEarned: xpEarned,
            isCompleted: isCompleted,
            title: title,
            imageURL: imageURL,
            feedback: feedback, scenarioId: scenarioId
        )
        addActivity(activity)
    }

    func clearHistory() {
        activities = []
        Task {
            await deleteAllActivitiesFromSupabase()
        }
    }

    /// Attach feedback to the most recent activity matching the given session type.
    /// Used by FeedbackCollectionViewController after the backend analysis completes.
    func attachFeedbackToLatestActivity(type: ActivityType, feedback: SessionFeedback) {
        guard let index = activities.lastIndex(where: { $0.type == type && $0.feedback == nil }) else {
            return
        }

        // Create a new Activity with the feedback attached
        let old = activities[index]
        let updated = Activity(
            type: old.type,
            date: old.date,
            topic: old.topic,
            duration: old.duration,
            xpEarned: old.xpEarned,
            isCompleted: old.isCompleted,
            title: old.title,
            imageURL: old.imageURL,
            roleplaySession: old.roleplaySession,
            feedback: feedback,
            scenarioId: old.scenarioId
        )
        // Preserve the original ID
        var mutableUpdated = updated
        mutableUpdated.setID(old.id)
        activities[index] = mutableUpdated
        NotificationCenter.default.post(name: HistoryDataModel.historyDataLoadedNotification, object: nil)
    }

    // MARK: - Supabase Operations

    private func loadHistory() async {
        guard let userId = UserDataModel.shared.getCurrentUser()?.id else {
            activities = []
            isLoaded = true
            NotificationCenter.default.post(name: HistoryDataModel.historyDataLoadedNotification, object: nil)
            return
        }

        do {
            let rows: [ActivityRow] = try await supabase
                .from(SupabaseTable.activities)
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("date", ascending: false)
                .execute()
                .value
            activities = rows.map { $0.toActivity() }
            isLoaded = true
            
            NotificationCenter.default.post(name: HistoryDataModel.historyDataLoadedNotification, object: nil)
        } catch {
            print("❌ Failed to load activities: \(error.localizedDescription)")
            activities = []
            isLoaded = true
            NotificationCenter.default.post(name: HistoryDataModel.historyDataLoadedNotification, object: nil)
        }
    }

    private func insertActivityInSupabase(_ activity: Activity) async {
        guard let userId = UserDataModel.shared.getCurrentUser()?.id else { return }

        do {
            let row = ActivityRow(from: activity, userId: userId)
            try await supabase
                .from(SupabaseTable.activities)
                .insert(row)
                .execute()
        } catch {
            print("❌ Failed to insert activity: \(error.localizedDescription)")
        }
    }

    private func deleteAllActivitiesFromSupabase() async {
        guard let userId = UserDataModel.shared.getCurrentUser()?.id else { return }

        do {
            try await supabase
                .from(SupabaseTable.activities)
                .delete()
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            print("❌ Failed to clear activities: \(error.localizedDescription)")
        }
    }

    // MARK: - Sample Data

    private func loadSampleActivities() -> [Activity] {

        let activity2 = Activity(
            type: .jam,
            date: Date().addingTimeInterval(-172800),
            topic: "Space Exploration",
            duration: 3,
            xpEarned: 6,
            isCompleted: true,
            title: "Jam Session",
            imageURL: "jam_sample"
        )

        let activity3 = Activity(
            type: .roleplay,
            date: Date().addingTimeInterval(-259200),
            topic: "Interview Practice",
            duration: 4,
            xpEarned: 12,
            isCompleted: true,
            title: "Roleplay",
            imageURL: "roleplay_sample"
        )

        return [ activity2, activity3]
    }
}

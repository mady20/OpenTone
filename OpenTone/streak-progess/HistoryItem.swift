
import Foundation

struct HistoryItem {
    let title: String          // e.g. "2 Min Session"
    let subtitle: String       // e.g. "You completed 2 min session"
    let topic: String          // e.g. "Time Travel"
    let duration: String       // e.g. "2 min"
    let iconName: String       // e.g. "mic.fill"
    let date: Date             // timestamp of the session
    let activityType: ActivityType?   // .call, .jam, .roleplay
    let scenarioId: UUID?      // for roleplay resume
    let isCompleted: Bool
    let feedback: SessionFeedback?

    init(title: String,
         subtitle: String,
         topic: String,
         duration: String,
         iconName: String,
         date: Date = Date(),
         activityType: ActivityType? = nil,
         scenarioId: UUID? = nil,
         isCompleted: Bool = true,
         feedback: SessionFeedback? = nil) {

        self.title = title
        self.subtitle = subtitle
        self.topic = topic
        self.duration = duration
        self.iconName = iconName
        self.date = date
        self.activityType = activityType
        self.scenarioId = scenarioId
        self.isCompleted = isCompleted
        self.feedback = feedback
    }
}
extension HistoryItem {
    var durationText: String { duration }

    /// Formatted time string like "2:30 PM"
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}


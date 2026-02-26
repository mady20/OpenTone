import Foundation

class SessionProgressManager {

    static let shared = SessionProgressManager()
    private init() {}

    enum SessionType: String {
        case aiCall
        case twoMinJam
        case roleplay

        var durationInMinutes: Int {
            switch self {
            case .aiCall: return 10
            case .twoMinJam: return 2
            case .roleplay: return 15
            }
        }

        var xp: Int {
            switch self {
            case .aiCall: return 20
            case .twoMinJam: return 15
            case .roleplay: return 25
            }
        }

        var title: String {
            switch self {
            case .aiCall: return "AI Call"
            case .twoMinJam: return "2 Min Session"
            case .roleplay: return "Roleplay"
            }
        }

        var iconName: String {
            switch self {
            case .aiCall: return "phone.fill"
            case .twoMinJam: return "mic.fill"
            case .roleplay: return "theatermasks.fill"
            }
        }
    }

    func markCompleted(_ type: SessionType, topic: String, actualDurationMinutes: Int? = nil) {

        let finalDuration = actualDurationMinutes ?? type.durationInMinutes

        StreakDataModel.shared.logSession(
            title: type.title,
            subtitle: "You completed a session",
            topic: topic,
            durationMinutes: finalDuration,
            xp: type.xp,
            iconName: type.iconName
        )
    }
}

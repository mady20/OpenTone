import Foundation

struct JamSession: Identifiable, Equatable, Codable {

    static let availableTopics: [String] = [
        "The Future of Technology",
        "Climate Change and Its Impact",
        "The Role of Art in Society",
        "Exploring Space: The Next Frontier",
        "The Evolution of Education",
        "How Social Media Shapes Communication",
        "Should Remote Work Remain the Default?",
        "The Value of Learning a Second Language",
        "Is Artificial Intelligence Creative?",
        "Building Healthy Daily Habits",
        "The Power of Storytelling in Leadership",
        "How Sports Teach Life Skills",
        "What Makes a Great Team Player",
        "The Importance of Mental Health Awareness",
        "Can Cities Become Fully Sustainable?",
        "Why Public Speaking Matters in Every Career",
        "The Impact of Fast Fashion",
        "Should Students Have Homework Every Day?",
        "How Travel Changes Perspective",
        "The Future of Electric Vehicles",
        "Can Video Games Be Educational?",
        "The Benefits of Volunteering",
        "How to Handle Failure Productively",
        "The Ethics of Facial Recognition",
        "Are Smart Homes Really Smart?",
        "The Future of Renewable Energy",
        "How Music Affects Mood and Focus",
        "The Value of Reading Fiction",
        "Should Exams Be Replaced by Projects?",
        "What Makes an Idea Go Viral?",
        "The Importance of Financial Literacy",
        "How to Build Better Listening Skills",
        "Is Competition Good for Growth?",
        "The Future of Food Technology",
        "Should Public Transport Be Free?",
        "How to Stay Calm Under Pressure",
        "The Role of Design in Everyday Life",
        "Can Technology Reduce Loneliness?",
        "Why Sleep Is a Performance Tool",
        "The Pros and Cons of Influencer Culture",
        "How Climate Action Starts Locally",
        "What Makes a Brand Trustworthy",
        "The Role of Ethics in Business Decisions",
        "Should Coding Be Taught in Every School?",
        "The Future of Human-Machine Collaboration",
        "How to Give and Receive Feedback Well",
        "Can Space Tourism Become Mainstream?",
        "The Psychology of Motivation",
        "How Communities Recover After Disasters",
        "Why Critical Thinking Is a Superpower",
        "The Impact of AI on Jobs",
        "How to Speak Clearly in High-Stakes Moments",
        "The Value of Curiosity in Learning",
        "Should Schools Prioritize Life Skills?",
        "The Future of Healthcare Technology",
        "How to Build Confidence Through Practice",
        "The Role of Creativity in Problem Solving",
        "What Makes a Product Truly User-Friendly",
        "Can Education Close Social Inequality?"
    ]

    private(set) var id: UUID
    let userId: UUID
    
    /// Override the auto-generated UUID (used when loading from Supabase).
    mutating func setID(_ newID: UUID) { id = newID }

    var topic: String
    var suggestions: [String]

    var phase: JamPhase

    var secondsLeft: Int

    var startedPrepAt: Date?
    var startedSpeakingAt: Date?
    var endedAt: Date?

    init(
        userId: UUID,
        topic: String,
        suggestions: [String],
        phase: JamPhase = .preparing,
        secondsLeft: Int = 10
    ) {
        self.id = UUID()
        self.userId = userId
        self.topic = topic
        self.suggestions = suggestions
        self.phase = phase
        self.secondsLeft = secondsLeft
        self.startedPrepAt = Date()
        self.startedSpeakingAt = nil
        self.endedAt = nil
    }

    static func == (lhs: JamSession, rhs: JamSession) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, userId, topic, suggestions, phase, secondsLeft
        case startedPrepAt, startedSpeakingAt, endedAt
    }
}

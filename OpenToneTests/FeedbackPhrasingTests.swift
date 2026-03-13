import XCTest
@testable import OpenTone

final class FeedbackPhrasingTests: XCTestCase {

    func testFeedbackMapperProducesCoherentSummaryText() {
        let response = SpeechAnalysisResponse(
            transcript: "I practiced speaking about my day.",
            metrics: SpeechMetrics(
                wpm: 128,
                totalWords: 24,
                durationS: 11,
                fillerRatePerMin: 1.2,
                fillers: 1,
                pauses: 1,
                avgPauseS: 0.8,
                veryLongPauses: 0,
                repetitions: 0,
                fillerExamples: [FillerExample(word: "um", timestamp: 3)],
                pauseExamples: [PauseExample(start: 6, end: 6.8, duration: 0.8)]
            ),
            coaching: SpeechCoaching(
                scores: CoachingScores(fluency: 84, confidence: 82, clarity: 88),
                primaryIssue: "Minor hesitation in transitions",
                primaryIssueTitle: "Pause and Hesitation Control",
                secondaryIssues: [],
                strengths: ["Your pace stayed conversational."],
                suggestions: ["Use one breath before transitions."],
                evidence: [],
                llmCoaching: nil
            ),
            progress: SpeechProgress(
                deltas: Deltas(wpm: 2, fillers: 0.5, pauses: 0.2),
                overallDirection: "improving",
                weeklySummary: "Improving trend this week."
            )
        )

        let mapped = FeedbackMapper.toFeedback(response)

        XCTAssertEqual(mapped.rating, .good)
        XCTAssertEqual(mapped.fillerWordCount, 1)
        XCTAssertEqual(mapped.pauseCount, 1)
        XCTAssertTrue((mapped.aiFeedbackSummary ?? "").contains("Improving"))
    }
}

import XCTest
@testable import OpenTone

private struct FailingProvider: RemoteFeedbackProvider {
    let name: String = "failing"
    func isAvailable() -> Bool { true }
    func enhance(_ base: SpeechAnalysisResponse, input: FeedbackEngineInput) async throws -> SpeechAnalysisResponse {
        struct TestError: Error {}
        throw TestError()
    }
}

private final class StubCoreEngine: FeedbackEngine {
    func analyze(_ input: FeedbackEngineInput) async -> SpeechAnalysisResponse {
        SpeechAnalysisResponse(
            transcript: input.transcript,
            metrics: SpeechMetrics(
                wpm: 120,
                totalWords: 20,
                durationS: 10,
                fillerRatePerMin: 0,
                fillers: 0,
                pauses: 0,
                avgPauseS: 0,
                veryLongPauses: 0,
                repetitions: 0,
                fillerExamples: [],
                pauseExamples: []
            ),
            coaching: SpeechCoaching(
                scores: CoachingScores(fluency: 90, confidence: 88, clarity: 92),
                primaryIssue: "None",
                primaryIssueTitle: "Harmless Variation",
                secondaryIssues: [],
                strengths: ["Steady delivery"],
                suggestions: ["Keep practicing"],
                evidence: [],
                llmCoaching: nil
            ),
            progress: SpeechProgress(
                deltas: Deltas(wpm: 0, fillers: 0, pauses: 0),
                overallDirection: "mixed",
                weeklySummary: "Baseline"
            )
        )
    }
}

final class ProviderFallbackTests: XCTestCase {

    func testCoordinatorFallsBackToCoreWhenProviderFails() async {
        let coordinator = FeedbackEngineCoordinator(coreEngine: StubCoreEngine(), remoteProviders: [FailingProvider()])
        let response = await coordinator.analyze(
            FeedbackEngineInput(
                transcript: "test speech",
                topic: "test",
                durationS: 10,
                userId: "u3",
                sessionId: "s3",
                mode: .jam,
                turnSummaries: []
            )
        )

        XCTAssertEqual(response.coaching.primaryIssueTitle, "Harmless Variation")
        XCTAssertEqual(response.metrics.totalWords, 20)
    }
}

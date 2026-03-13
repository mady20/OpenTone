import Foundation

final class GeminiFeedbackProvider: RemoteFeedbackProvider {

    let name: String = "gemini"

    func isAvailable() -> Bool {
        GeminiAPIKeyManager.shared.hasAPIKey
    }

    func enhance(_ base: SpeechAnalysisResponse, input: FeedbackEngineInput) async throws -> SpeechAnalysisResponse {
        guard !input.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return base
        }

        let feedback = try await GeminiService.shared.generateJamFeedback(
            transcript: input.transcript,
            topic: input.topic.isEmpty ? "General speaking" : input.topic,
            durationSeconds: input.durationS
        )

        let suggestionsFromMistakes = (feedback.mistakes ?? []).map { $0.correction }.filter { !$0.isEmpty }
        let mergedSuggestions = Array(uniquePreservingOrder(suggestionsFromMistakes + base.coaching.suggestions).prefix(5))

        let llmCoaching = LLMCoaching(
            primaryIssue: feedback.comments,
            suggestions: mergedSuggestions,
            improvedSentence: feedback.aiFeedbackSummary ?? "",
            strengths: base.coaching.strengths,
            difficultyLevel: "adaptive",
            source: "gemini"
        )

        let coaching = SpeechCoaching(
            scores: base.coaching.scores,
            primaryIssue: base.coaching.primaryIssue,
            primaryIssueTitle: base.coaching.primaryIssueTitle,
            secondaryIssues: base.coaching.secondaryIssues,
            strengths: base.coaching.strengths,
            suggestions: mergedSuggestions,
            evidence: base.coaching.evidence,
            llmCoaching: llmCoaching
        )

        let progress = SpeechProgress(
            deltas: base.progress.deltas,
            overallDirection: base.progress.overallDirection,
            weeklySummary: feedback.aiFeedbackSummary ?? base.progress.weeklySummary
        )

        return SpeechAnalysisResponse(
            transcript: base.transcript,
            metrics: base.metrics,
            coaching: coaching,
            progress: progress
        )
    }

    private func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

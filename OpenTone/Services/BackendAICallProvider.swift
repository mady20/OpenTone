import Foundation

final class BackendAICallProvider: AICallLLMProvider {

    let id: AICallProviderID = .backend

    func isAvailable() -> Bool {
        true
    }

    func startSession(_ input: AICallStartInput) async throws -> AICallStartResult {
        let response = try await BackendSpeechService.shared.startChat(
            mode: "call",
            scenario: input.scenario,
            difficulty: input.difficulty
        )
        return AICallStartResult(assistantText: response.message, provider: id)
    }

    func generateTurn(_ input: AICallTurnInput) async throws -> AICallTurnResult {
        let response = try await BackendSpeechService.shared.analyzeChat(
            transcript: input.transcript,
            durationS: input.durationS,
            userId: input.userId,
            mode: "call",
            scenario: input.scenario,
            difficulty: input.difficulty,
            conversationHistory: input.conversationHistory
        )

        let aiText = response.llmReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (response.coaching.llmCoaching?.improvedSentence ?? "Could you say that again?")
            : response.llmReply

        return AICallTurnResult(
            userTranscript: response.transcript,
            assistantText: aiText,
            metrics: response.metrics,
            provider: id
        )
    }
}

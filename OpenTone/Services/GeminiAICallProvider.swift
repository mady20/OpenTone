import Foundation

final class GeminiAICallProvider: AICallLLMProvider {

    let id: AICallProviderID = .gemini

    func isAvailable() -> Bool {
        GeminiAPIKeyManager.shared.hasAPIKey
    }

    func startSession(_ input: AICallStartInput) async throws -> AICallStartResult {
        let opening = try await GeminiService.shared.startAICallSession(
            scenario: input.scenario,
            difficulty: input.difficulty
        )
        return AICallStartResult(assistantText: opening, provider: id)
    }

    func generateTurn(_ input: AICallTurnInput) async throws -> AICallTurnResult {
        let reply = try await GeminiService.shared.generateAICallTurnResponse(
            userText: input.transcript,
            scenario: input.scenario,
            difficulty: input.difficulty
        )

        return AICallTurnResult(
            userTranscript: input.transcript,
            assistantText: reply,
            metrics: nil,
            provider: id
        )
    }
}

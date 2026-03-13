import Foundation

enum AICallProviderID: String {
    case backend
}

struct AICallStartInput {
    let userId: String
    let scenario: String
    let difficulty: String
}

struct AICallTurnInput {
    let userId: String
    let transcript: String
    let durationS: Double
    let scenario: String
    let difficulty: String
    let conversationHistory: [[String: String]]
}

struct AICallStartResult {
    let assistantText: String
    let provider: AICallProviderID
}

struct AICallTurnResult {
    let userTranscript: String
    let assistantText: String
    let metrics: SpeechMetrics?
    let provider: AICallProviderID
}

protocol AICallLLMProvider {
    var id: AICallProviderID { get }
    func isAvailable() -> Bool
    func startSession(_ input: AICallStartInput) async throws -> AICallStartResult
    func generateTurn(_ input: AICallTurnInput) async throws -> AICallTurnResult
}

struct AICallProviderPolicy {
    let primary: AICallProviderID
    let fallbacks: [AICallProviderID]
    let requirePrimary: Bool
    let allowFallbackOnPrimaryFailure: Bool

    static func fromConfig() -> AICallProviderPolicy {
        let primaryRaw = (UserDefaults.standard.string(forKey: "opentone.aiCall.primaryProvider")
            ?? (Bundle.main.object(forInfoDictionaryKey: "AICallPrimaryProvider") as? String)
            ?? "backend").lowercased()

        let fallbackRaw = (UserDefaults.standard.string(forKey: "opentone.aiCall.fallbackProviders")
            ?? (Bundle.main.object(forInfoDictionaryKey: "AICallFallbackProviders") as? String)
            ?? "").lowercased()

        let requirePrimary = (UserDefaults.standard.object(forKey: "opentone.aiCall.requirePrimaryProvider") as? Bool)
            ?? (Bundle.main.object(forInfoDictionaryKey: "AICallRequirePrimaryProvider") as? Bool)
            ?? true

        let allowFallback = (UserDefaults.standard.object(forKey: "opentone.aiCall.allowFallbackOnPrimaryFailure") as? Bool)
            ?? (Bundle.main.object(forInfoDictionaryKey: "AICallAllowFallbackOnPrimaryFailure") as? Bool)
            ?? false

        let primary = AICallProviderID(rawValue: primaryRaw) ?? .backend
        let fallbacks = fallbackRaw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { AICallProviderID(rawValue: $0) }
            .filter { $0 != primary }

        return AICallProviderPolicy(
            primary: primary,
            fallbacks: fallbacks,
            requirePrimary: requirePrimary,
            allowFallbackOnPrimaryFailure: allowFallback
        )
    }
}

enum AICallOrchestratorError: LocalizedError {
    case providerUnavailable(AICallProviderID)
    case providerFailed(AICallProviderID, String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let id):
            return "\(id.rawValue.capitalized) provider is unavailable."
        case .providerFailed(let id, let message):
            return "\(id.rawValue.capitalized) provider failed: \(message)"
        }
    }
}

enum AICallProviderFactory {

    static func makeOrchestrator(policy: AICallProviderPolicy = .fromConfig()) -> AICallOrchestrator {
        let providers: [AICallProviderID: AICallLLMProvider] = [
            .backend: BackendAICallProvider()
        ]

        return AICallOrchestrator(policy: policy, providers: providers)
    }
}

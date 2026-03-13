import Foundation

enum FeedbackSessionMode: String {
    case jam
    case aiCall
    case roleplay
}

struct FeedbackEngineInput {
    let transcript: String
    let topic: String
    let durationS: Double
    let userId: String
    let sessionId: String
    let mode: FeedbackSessionMode
    let turnSummaries: [SessionTurnSummary]
}

protocol FeedbackEngine {
    func analyze(_ input: FeedbackEngineInput) async -> SpeechAnalysisResponse
}

protocol RemoteFeedbackProvider {
    var name: String { get }
    func isAvailable() -> Bool
    func enhance(_ base: SpeechAnalysisResponse, input: FeedbackEngineInput) async throws -> SpeechAnalysisResponse
}

struct FeedbackEnginePolicy {
    let enableGeminiEnhancement: Bool

    static func fromConfig() -> FeedbackEnginePolicy {
        let plistFlag = Bundle.main.object(forInfoDictionaryKey: "EnableGeminiFeedbackEnhancement") as? Bool
        let userDefaultFlag = UserDefaults.standard.object(forKey: "opentone.feedback.gemini.enabled") as? Bool
        return FeedbackEnginePolicy(enableGeminiEnhancement: userDefaultFlag ?? plistFlag ?? false)
    }
}

final class FeedbackEngineCoordinator: FeedbackEngine {

    private let coreEngine: FeedbackEngine
    private let remoteProviders: [RemoteFeedbackProvider]

    init(coreEngine: FeedbackEngine, remoteProviders: [RemoteFeedbackProvider]) {
        self.coreEngine = coreEngine
        self.remoteProviders = remoteProviders
    }

    func analyze(_ input: FeedbackEngineInput) async -> SpeechAnalysisResponse {
        var response = await coreEngine.analyze(input)

        for provider in remoteProviders where provider.isAvailable() {
            do {
                response = try await provider.enhance(response, input: input)
            } catch {
                continue
            }
        }

        return response
    }
}

enum FeedbackEngineFactory {

    static func makeDefault() -> FeedbackEngine {
        let policy = FeedbackEnginePolicy.fromConfig()
        let onDevice = OnDeviceFeedbackEngine()

        var providers: [RemoteFeedbackProvider] = []
        if policy.enableGeminiEnhancement {
            providers.append(GeminiFeedbackProvider())
        }

        return FeedbackEngineCoordinator(coreEngine: onDevice, remoteProviders: providers)
    }
}

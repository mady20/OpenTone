import Foundation

// MARK: - Request

struct AnalyzeRequest: Encodable {
    let audioURL: String?
    let transcript: String?
    let durationS: Double?
    let userId: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case audioURL   = "audio_url"
        case transcript = "transcript"
        case durationS  = "duration_s"
        case userId     = "user_id"
        case sessionId  = "session_id"
    }
}

// MARK: - Metrics

struct SpeechMetrics: Codable {
    let wpm: Double
    let totalWords: Int
    let durationS: Double
    let fillerRatePerMin: Double
    let fillers: Int
    let pauses: Int
    let avgPauseS: Double
    let veryLongPauses: Int
    let repetitions: Int
    let fillerExamples: [FillerExample]
    let pauseExamples: [PauseExample]

    enum CodingKeys: String, CodingKey {
        case wpm, fillers, pauses, repetitions
        case totalWords        = "total_words"
        case durationS         = "duration_s"
        case fillerRatePerMin  = "filler_rate_per_min"
        case avgPauseS         = "avg_pause_s"
        case veryLongPauses    = "very_long_pauses"
        case fillerExamples    = "filler_examples"
        case pauseExamples     = "pause_examples"
    }
}

struct FillerExample: Codable {
    let word: String
    let timestamp: Double
}

struct PauseExample: Codable {
    let start: Double
    let end: Double
    let duration: Double
}

// MARK: - Pronunciation

/// Word-level pronunciation score from the phoneme alignment engine.
struct PronunciationWord: Codable {
    let word: String
    let score: Double?            // 0–100, nil if engine unavailable
    let expectedPhonemes: [String]
    let spokenPhonemes: [String]
    let errorPhonemes: [String]
    let category: String?         // "vowel_distortion" | "consonant_substitution" | "missing_phoneme" | "extra_phoneme"
    let start: Double
    let end: Double

    enum CodingKeys: String, CodingKey {
        case word, score, category, start, end
        case expectedPhonemes = "expected_phonemes"
        case spokenPhonemes   = "spoken_phonemes"
        case errorPhonemes    = "error_phonemes"
    }

    /// True if this word's pronunciation score is below the good threshold.
    var isMispronounced: Bool { (score ?? 100) < 70 }
    var isWeakly: Bool { let s = score ?? 100; return s >= 70 && s < 85 }

    /// Human-readable category label.
    var categoryLabel: String {
        switch category {
        case "vowel_distortion":      return "Vowel distortion"
        case "consonant_substitution": return "Consonant substitution"
        case "missing_phoneme":       return "Missing phoneme"
        case "extra_phoneme":         return "Extra phoneme"
        case "stress_error":          return "Stress error"
        default: return "Pronunciation issue"
        }
    }
}

struct PronunciationResult: Codable {
    let avgScore: Double?
    let words: [PronunciationWord]
    let worstWords: [PronunciationWord]

    enum CodingKeys: String, CodingKey {
        case avgScore   = "avg_score"
        case words
        case worstWords = "worst_words"
    }
}

// MARK: - Coaching

struct SpeechCoaching: Codable {
    let scores: CoachingScores
    let primaryIssue: String
    let primaryIssueTitle: String
    let secondaryIssues: [String]
    let strengths: [String]
    let suggestions: [String]
    let evidence: [EvidenceItem]
    let llmCoaching: LLMCoaching?

    enum CodingKeys: String, CodingKey {
        case scores, strengths, suggestions, evidence
        case primaryIssue      = "primary_issue"
        case primaryIssueTitle = "primary_issue_title"
        case secondaryIssues   = "secondary_issues"
        case llmCoaching       = "llm_coaching"
    }
}

struct CoachingScores: Codable {
    let fluency: Double
    let confidence: Double
    let clarity: Double

    /// 0–100 overall composite
    var overall: Double { (fluency + confidence + clarity) / 3.0 }
}

struct EvidenceItem: Codable {
    let type: String        // "filler" | "pause" | "repetition" | "pronunciation"
    let timestamp: Double
    let text: String        // e.g. "00:14 — \"um\""
}

/// Enriched coaching from the local LLM (Ollama).
struct LLMCoaching: Codable {
    let primaryIssue: String
    let suggestions: [String]
    let improvedSentence: String
    let strengths: [String]
    let difficultyLevel: String
    let source: String          // "llm" | "fallback"

    enum CodingKeys: String, CodingKey {
        case suggestions, strengths, source
        case primaryIssue       = "primary_issue"
        case improvedSentence   = "improved_sentence"
        case difficultyLevel    = "difficulty_level"
    }
}

// MARK: - Progress

struct SpeechProgress: Codable {
    let deltas: Deltas
    let overallDirection: String  // "improving" | "declining" | "mixed"
    let weeklySummary: String

    enum CodingKeys: String, CodingKey {
        case deltas
        case overallDirection = "overall_direction"
        case weeklySummary    = "weekly_summary"
    }

    var directionArrow: String {
        switch overallDirection {
        case "improving": return "↑"
        case "declining": return "↓"
        default:          return "→"
        }
    }
}

struct Deltas: Codable {
    let wpm: Double
    let fillers: Double
    let pauses: Double
    let pronunciation: Double

    var fillersDescription: String? {
        guard abs(fillers) >= 0.1 else { return nil }
        let dir = fillers > 0 ? "fewer" : "more"
        return String(format: "%.1f \(dir) fillers/min", abs(fillers))
    }

    var wpmDescription: String? {
        guard abs(wpm) >= 1 else { return nil }
        let dir = wpm > 0 ? "faster" : "slower"
        return String(format: "%+.0f WPM (\(dir))", wpm)
    }

    var pronunciationDescription: String? {
        guard abs(pronunciation) >= 1 else { return nil }
        let dir = pronunciation > 0 ? "improved" : "dropped"
        return String(format: "Pronunciation \(dir) by %.0f%%", abs(pronunciation))
    }
}

// MARK: - Full Analyze Response

struct SpeechAnalysisResponse: Codable {
    let transcript: String
    let metrics: SpeechMetrics
    let coaching: SpeechCoaching
    let progress: SpeechProgress
    let pronunciation: PronunciationResult?
}

// MARK: - Transcribe Response (Quick ASR)

struct TranscribeResponse: Codable {
    let transcript: String
    let duration_s: Double
}

// MARK: - Chat Response (1-on-1 AI Call)

struct ChatResponse: Codable {
    let transcript: String
    let metrics: SpeechMetrics
    let pronunciation: PronunciationResult?
    let coaching: SpeechCoaching
    let llmReply: String      // the AI's reply text
    let audioWavB64: String   // base64 WAV for playback

    enum CodingKeys: String, CodingKey {
        case transcript, metrics, pronunciation, coaching
        case llmReply    = "llm_reply"
        case audioWavB64 = "audio_wav_b64"
    }
}

// MARK: - User Profile

struct UserSpeechProfile: Codable {
    let userId: String
    let avgWpm: Double
    let avgFillerRate: Double
    let avgPause: Double
    let avgRepetition: Double
    let avgPronunciationScore: Double
    let fluencyScore: Double
    let confidenceScore: Double
    let clarityScore: Double
    let sessionsCount: Int
    let recentScores: [Double]?

    enum CodingKeys: String, CodingKey {
        case userId                  = "user_id"
        case avgWpm                  = "avg_wpm"
        case avgFillerRate           = "avg_filler_rate"
        case avgPause                = "avg_pause"
        case avgRepetition           = "avg_repetition"
        case avgPronunciationScore   = "avg_pronunciation_score"
        case fluencyScore            = "fluency_score"
        case confidenceScore         = "confidence_score"
        case clarityScore            = "clarity_score"
        case sessionsCount           = "sessions_count"
        case recentScores            = "recent_scores"
    }

    var overallScore: Double { (fluencyScore + confidenceScore + clarityScore) / 3.0 }
}

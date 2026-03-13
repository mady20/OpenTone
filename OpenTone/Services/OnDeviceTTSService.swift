import Foundation
import AVFoundation
import KokoroSwift
import MLX

class OnDeviceTTSService {
    static let shared = OnDeviceTTSService()

    private var kokoroTTS: KokoroTTS?
    private var isPlaying = false
    private var isModelLoaded = false
    private var modelLoadingTask: Task<Void, Error>?
    private var currentVoice: MLXArray?
    private var audioEngine: AVAudioEngine?
    private var audioPlayer: AVAudioPlayerNode?

    private init() {
        setupAudioEngine()
    }
    
    /// Setup AVAudioEngine for playback
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()
        audioEngine?.attach(audioPlayer!)
        audioEngine?.connect(audioPlayer!, to: audioEngine!.mainMixerNode, format: nil)
    }

    /// Load the Kokoro models
    func loadModel() async throws {
        if isModelLoaded { return }
        if let existingTask = modelLoadingTask {
            _ = try await existingTask.value
            return
        }

        let task = Task<Void, Error> {
            do {
                print("Kokoro TTS: Loading model...")
                let modelDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("kokoro_model")
                
                if !FileManager.default.fileExists(atPath: modelDir.path) {
                    print("Kokoro TTS: Model directory not found at \(modelDir.path)")
                }

                // Initialize Kokoro TTS with misaki G2P processor
                self.kokoroTTS = KokoroTTS(modelPath: modelDir, g2p: .misaki)
                
                // Load or create voice embedding
                self.currentVoice = MLXArray(zeros: [1, 256])
                
                self.isModelLoaded = true
                print("Kokoro TTS: Model loaded successfully")
            } catch {
                print("Kokoro TTS: Failed to load model - \(error)")
                throw error
            }
        }
        modelLoadingTask = task
        _ = try await task.value
    }

    /// Synthesize and play text using Kokoro TTS
    func speak(text: String, voiceName: String = "af_heart") async throws {
        try await loadModel()
        
        guard let kokoro = kokoroTTS else {
            throw NSError(domain: "OnDeviceTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "TTS Engine not initialized"])
        }
        guard let voice = currentVoice else {
            throw NSError(domain: "OnDeviceTTSService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Voice not loaded"])
        }
        
        isPlaying = true
        defer { isPlaying = false }

        print("Kokoro TTS: Starting synthesis for text: \(text)")
        
        // Generate audio off the main thread
        let result = try await Task.detached {
            return try kokoro.generateAudio(voice: voice, language: .enUS, text: text, speed: 1.0)
        }.value

        let floatArray = result.0
        print("Kokoro TTS: Synthesis completed, generating \(floatArray.count) samples")
        
        try await playAudioData(floatArray, sampleRate: Float(KokoroTTS.Constants.samplingRate))
    }

    /// Convert float PCM array to audio buffer and play
    private func playAudioData(_ data: [Float], sampleRate: Float) async throws {
        guard let audioEngine = audioEngine, let audioPlayer = audioPlayer else {
            throw NSError(domain: "OnDeviceTTSService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Audio engine not initialized"])
        }

        // Create audio format
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)
        guard let format = format else {
            throw NSError(domain: "OnDeviceTTSService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Could not create audio format"])
        }

        // Create audio buffer
        let frameCount = AVAudioFrameCount(data.count)
        guard let audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "OnDeviceTTSService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Could not create audio buffer"])
        }

        // Copy audio data
        audioBuffer.frameLength = frameCount
        let channels = audioBuffer.floatChannelData
        memcpy(channels![0], data, Int(frameCount) * MemoryLayout<Float>.stride)

        // Start audio engine if not running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Error starting audio engine: \(error)")
            }
        }

        // Schedule and play buffer
        audioPlayer.scheduleBuffer(audioBuffer, completionHandler: nil)
        if !audioPlayer.isPlaying {
            audioPlayer.play()
        }

        print("Kokoro TTS: Audio playback started")
    }

    func stopPlaying() {
        isPlaying = false
        audioPlayer?.stop()
    }
}

import UIKit
import AVFoundation
import AVFAudio
import Speech

// MARK: - DisplayLinkProxy (prevents CADisplayLink → VC retain cycle)
private final class DisplayLinkProxy {
    weak var target: AICallController?
    init(target: AICallController) { self.target = target }
    @objc func step(_ link: CADisplayLink) { target?.updateAnimation() }
}

final class AICallController: UIViewController {

    // MARK: - State Machine

    private enum State {
        case idle
        case listening
        case processing
        case speaking
    }

    private var currentState: State = .idle {
        didSet { updateStatusLabel() }
    }

    // MARK: - Audio / Speech

    private var audioPlayer: AVAudioPlayer?

    private var isMuted = false
    private var isListening = false
    private var isProcessing = false   // re-entry guard for handleSilenceDetected

    // VAD (Voice Activity Detection) State
    private var lastVoiceUpdate: Date = .distantPast
    private var hasSpoken = false      // true once voice level crosses threshold
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 3.5
    private let maxListenDuration: TimeInterval = 45.0  // safety cap

    /// Cached audio from the last failed turn — enables tap-to-retry.
    private var lastFailedAudioData: Data?
    private var isRetrying = false
    private var isClosing = false

    // MARK: - Ring Animation

    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private let ringLayer = CAShapeLayer()
    private let pulseLayer = CAShapeLayer()

    private var smoothedLevel: CGFloat = 0.1
    private let smoothingFactor: CGFloat = 0.15
    private let baseRadius: CGFloat = 80
    private let maxExpansion: CGFloat = 40

    // MARK: - UI Elements

    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .medium)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.allowsSelection = true
        tv.showsVerticalScrollIndicator = false
        tv.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return tv
    }()

    private var muteButton: UIButton!
    private var closeButton: UIButton!

    // MARK: - Data

    private struct ChatBubble {
        enum Sender { case user, ai }
        let sender: Sender
        let text: String
    }

    private var chatBubbles: [ChatBubble] = []
    private var sessionTurnSummaries: [SessionTurnSummary] = []
    private var userTranscriptParts: [String] = []
    private var hasStartedConversation = false

    /// Conversation history sent to Ollama (/chat endpoint treats text turns).
    /// Each entry: ["role": "user"|"assistant", "content": "…"]
    private var conversationHistory: [[String: String]] = []

    /// Timestamp when the call started — used to compute call duration.
    private var callStartDate: Date = Date()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = AppColors.screenBackground

        setupRing()
        setupUI()
        
        AudioManager.shared.onAudioBuffer = { [weak self] buffer in
            self?.processAudio(buffer)
        }

        startDisplayLink()
        AudioManager.shared.requestPermissions { [weak self] granted in
            guard let self, granted else { return }
            self.beginSession()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ringLayer.frame = view.bounds
        pulseLayer.frame = view.bounds
        updateRing(radius: baseRadius)
    }

    deinit {
        displayLink?.invalidate()
        invalidateSilenceTimer()
        audioPlayer?.stop()
        if AudioManager.shared.isRecording {
            AudioManager.shared.stopRecording(autoTranscribe: false)
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Status label (above ring)
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -(baseRadius + 40))
        ])
        currentState = .idle

        // Chat table view (below ring)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ChatBubbleCell.self, forCellReuseIdentifier: ChatBubbleCell.id)
        view.addSubview(tableView)

        _ = view.bounds.midY + baseRadius + maxExpansion + 24

        // Buttons
        muteButton = makeButton(symbol: "mic.fill", action: #selector(toggleMute))
        closeButton = makeButton(symbol: "xmark", action: #selector(closeTapped))
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(muteButton)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Table view fills space between ring bottom and buttons
            tableView.topAnchor.constraint(equalTo: view.centerYAnchor, constant: baseRadius + maxExpansion + 24),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: muteButton.topAnchor, constant: -16),

            // Buttons at bottom
            muteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            muteButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            muteButton.widthAnchor.constraint(equalToConstant: 56),
            muteButton.heightAnchor.constraint(equalToConstant: 56),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            closeButton.widthAnchor.constraint(equalToConstant: 56),
            closeButton.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func makeButton(symbol: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        UIHelper.styleCircularIconButton(button, symbol: symbol)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func updateStatusLabel() {
        switch currentState {
        case .idle:       statusLabel.text = "Tap mic to start"
        case .listening:  statusLabel.text = "Listening…"
        case .processing: statusLabel.text = "Thinking…"
        case .speaking:   statusLabel.text = "Speaking…"
        }
    }

    // MARK: - Ring Animation

    private func setupRing() {
        // Subtle pulse ring behind main ring
        pulseLayer.strokeColor = AppColors.primary.withAlphaComponent(0.2).cgColor
        pulseLayer.fillColor = UIColor.clear.cgColor
        pulseLayer.lineWidth = 12
        pulseLayer.lineCap = .round
        pulseLayer.opacity = 1
        view.layer.addSublayer(pulseLayer)

        // Main ring
        ringLayer.strokeColor = AppColors.primary.cgColor
        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 8
        ringLayer.lineCap = .round
        ringLayer.opacity = 0.9
        view.layer.addSublayer(ringLayer)
    }

    private func updateRing(radius: CGFloat) {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY - 20)
        ringLayer.path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath

        // Pulse ring slightly larger
        pulseLayer.path = UIBezierPath(
            arcCenter: center,
            radius: radius + 6,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        ).cgPath
    }

    private func startDisplayLink() {
        let proxy = DisplayLinkProxy(target: self)
        displayLinkProxy = proxy
        displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc func updateAnimation() {
        let targetExpansion: CGFloat
        switch currentState {
        case .listening:
            targetExpansion = smoothedLevel * maxExpansion
        case .speaking:
            // Gentle pulsing when AI speaks
            let t = CACurrentMediaTime()
            targetExpansion = CGFloat(sin(t * 3.0) * 0.3 + 0.3) * maxExpansion * 0.5
        case .processing:
            // Slow breathe when processing
            let t = CACurrentMediaTime()
            targetExpansion = CGFloat(sin(t * 1.5) * 0.15 + 0.15) * maxExpansion
        case .idle:
            targetExpansion = 0
        }

        let currentRadius = baseRadius + targetExpansion
        updateRing(radius: currentRadius)

        // Update pulse opacity based on state
        let targetOpacity: Float = (currentState == .listening) ? 1.0 : 0.4
        pulseLayer.opacity += (targetOpacity - pulseLayer.opacity) * 0.05
    }

    // MARK: - Chat

    private func addBubble(_ bubble: ChatBubble) {
        chatBubbles.append(bubble)
        let indexPath = IndexPath(row: chatBubbles.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .fade)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }

    // MARK: - Permissions & Audio Session

    private func teardownAudio() {
        AudioManager.shared.onAudioBuffer = nil
        if AudioManager.shared.isRecording {
            AudioManager.shared.stopRecording(autoTranscribe: false)
        }
        audioPlayer?.stop()
    }

    // MARK: - Listening

    private func startListening() {
        guard !isMuted else { return }
        guard !isListening else { return }

        isListening = true
        isProcessing = false
        hasSpoken = false
        currentState = .listening

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        
        lastVoiceUpdate = Date()  
        startSilenceTimer()
        
        AudioManager.shared.startRecording()
    }

    private func stopListening() {
        guard isListening else { return }
        isListening = false
        invalidateSilenceTimer()
        AudioManager.shared.stopRecording(autoTranscribe: false)
    }

    private func restartListening() {
        stopListening()
        guard !isMuted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.isMuted else { return }
            self.startListening()
        }
    }

    // MARK: - Silence Detection

    private func startSilenceTimer() {
        invalidateSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkSilence()
        }
        RunLoop.main.add(silenceTimer!, forMode: .common)
    }

    private func invalidateSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func checkSilence() {
        guard isListening, !isProcessing else { return }

        let elapsed = Date().timeIntervalSince(lastVoiceUpdate)

        if hasSpoken && elapsed >= silenceThreshold {
            // User spoke then went silent → process their turn
            handleSilenceDetected()
        } else if !hasSpoken && elapsed >= maxListenDuration {
            // Safety cap: no voice detected for too long → prompt them
            handleSilenceDetected()
        }
    }

    // MARK: - Audio Processing (for ring animation)

    private func processAudio(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted, currentState == .listening, let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }

        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (db + 50) / 50)) // 0.0 to 1.0

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.smoothedLevel += (CGFloat(normalized) - self.smoothedLevel) * self.smoothingFactor
            
            // Voice detected — mark as spoken and reset silence timer
            if self.smoothedLevel > 0.12 {
                self.hasSpoken = true
                self.lastVoiceUpdate = Date()
            }
        }
    }

    // MARK: - Backend Integration

    private func beginSession() {
        guard !hasStartedConversation else { return }
        hasStartedConversation = true
        isProcessing = true
        currentState = .processing

        Task { [weak self] in
            guard let self, !self.isClosing else { return }
            do {
                let response = try await BackendSpeechService.shared.startChat(
                    mode: "call",
                    scenario: "Open Conversation",
                    difficulty: "medium"
                )

                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    let aiText = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !aiText.isEmpty {
                        self.conversationHistory.append(["role": "assistant", "content": aiText])
                        self.addBubble(ChatBubble(sender: .ai, text: aiText))
                    }

                    if let audioData = Data(base64Encoded: response.audioWavB64), !audioData.isEmpty {
                        self.speakAI(audioData: audioData)
                    } else {
                        self.isProcessing = false
                        self.startListening()
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    let fallback = "Hi! I'm ready to chat with you. How has your day been so far?"
                    self.conversationHistory.append(["role": "assistant", "content": fallback])
                    self.addBubble(ChatBubble(sender: .ai, text: fallback))

                    // Try to speak the fallback via backend TTS
                    Task { [weak self] in
                        guard let self, !self.isClosing else { return }
                        if let audioData = try? await BackendSpeechService.shared.tts(text: fallback), !audioData.isEmpty {
                            await MainActor.run { [weak self] in 
                                guard let self, !self.isClosing else { return }
                                self.speakAI(audioData: audioData) 
                            }
                        } else {
                            // TTS also failed — just start listening
                            await MainActor.run { [weak self] in
                                guard let self, !self.isClosing else { return }
                                self.isProcessing = false
                                self.startListening()
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleSilenceDetected() {
        guard !isProcessing, !isClosing else { return }  // prevent re-entry & post-close work
        isProcessing = true

        stopListening()
        
        guard let url = AudioManager.shared.lastRecordingURL, 
              let data = try? Data(contentsOf: url),
              data.count > 1000 else {  // minimum ~1KB to avoid sending noise/silence
            isProcessing = false
            restartListening()
            return
        }

        currentState = .processing

        Task { [weak self] in
            guard let self, !self.isClosing else { return }
            do {
                let userId = UserDataModel.shared.getCurrentUser()?.id.uuidString ?? "demo"
                let response = try await BackendSpeechService.shared.analyzeChat(
                    audioData: data,
                    userId: userId,
                    mode: "call",
                    scenario: "Open Conversation",
                    difficulty: "medium",
                    conversationHistory: self.conversationHistory
                )

                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    let userText = response.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userText.isEmpty {
                        self.addBubble(ChatBubble(sender: .user, text: userText))
                        self.conversationHistory.append(["role": "user", "content": userText])
                        self.userTranscriptParts.append(userText)
                        self.sessionTurnSummaries.append(
                            SessionTurnSummary(
                                transcript: userText,
                                totalWords: response.metrics.totalWords,
                                durationS: response.metrics.durationS,
                                fillers: response.metrics.fillers,
                                pauses: response.metrics.pauses,
                                avgPauseS: response.metrics.avgPauseS,
                                veryLongPauses: response.metrics.veryLongPauses,
                                repetitions: response.metrics.repetitions,
                                fillerExamples: response.metrics.fillerExamples,
                                pauseExamples: response.metrics.pauseExamples
                            )
                        )
                    }
                    
                    // Use the LLM's conversational reply; fall back to coaching only if empty
                    let aiText = response.llmReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (response.coaching.llmCoaching?.improvedSentence ?? "Could you say that again?")
                        : response.llmReply
                    self.conversationHistory.append(["role": "assistant", "content": aiText])
                    self.addBubble(ChatBubble(sender: .ai, text: aiText))
                    
                    if let audioData = Data(base64Encoded: response.audioWavB64), !audioData.isEmpty {
                        self.speakAI(audioData: audioData)
                    } else {
                        self.isProcessing = false
                        self.restartListening()
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    print("❌ Backend error:", error.localizedDescription)
                    // Cache the audio so the user can retry this turn
                    self.lastFailedAudioData = data
                    self.isRetrying = false
                    let msg = "⚠️ Connection issue — tap here to retry, or keep talking."
                    self.addBubble(ChatBubble(sender: .ai, text: msg))
                    self.isProcessing = false
                    self.restartListening()
                }
            }
        }
    }

    /// Retry the last failed conversation turn using cached audio data.
    private func retryLastTurn() {
        guard let cachedAudio = lastFailedAudioData, !isRetrying else { return }
        isRetrying = true
        lastFailedAudioData = nil
        isProcessing = true
        stopListening()
        currentState = .processing

        // Remove the retry-prompt bubble
        if let last = chatBubbles.last, last.sender == .ai, last.text.contains("tap here to retry") {
            chatBubbles.removeLast()
            tableView.deleteRows(at: [IndexPath(row: chatBubbles.count, section: 0)], with: .fade)
        }

        Task { [weak self] in
            guard let self, !self.isClosing else { return }
            do {
                let userId = UserDataModel.shared.getCurrentUser()?.id.uuidString ?? "demo"
                let response = try await BackendSpeechService.shared.analyzeChat(
                    audioData: cachedAudio,
                    userId: userId,
                    mode: "call",
                    scenario: "Open Conversation",
                    difficulty: "medium",
                    conversationHistory: self.conversationHistory
                )

                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    self.isRetrying = false
                    let userText = response.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !userText.isEmpty {
                        self.addBubble(ChatBubble(sender: .user, text: userText))
                        self.conversationHistory.append(["role": "user", "content": userText])
                        self.userTranscriptParts.append(userText)
                        self.sessionTurnSummaries.append(
                            SessionTurnSummary(
                                transcript: userText,
                                totalWords: response.metrics.totalWords,
                                durationS: response.metrics.durationS,
                                fillers: response.metrics.fillers,
                                pauses: response.metrics.pauses,
                                avgPauseS: response.metrics.avgPauseS,
                                veryLongPauses: response.metrics.veryLongPauses,
                                repetitions: response.metrics.repetitions,
                                fillerExamples: response.metrics.fillerExamples,
                                pauseExamples: response.metrics.pauseExamples
                            )
                        )
                    }

                    let aiText = response.llmReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? (response.coaching.llmCoaching?.improvedSentence ?? "Could you say that again?")
                        : response.llmReply
                    self.conversationHistory.append(["role": "assistant", "content": aiText])
                    self.addBubble(ChatBubble(sender: .ai, text: aiText))

                    if let audioData = Data(base64Encoded: response.audioWavB64), !audioData.isEmpty {
                        self.speakAI(audioData: audioData)
                    } else {
                        self.isProcessing = false
                        self.restartListening()
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, !self.isClosing else { return }
                    self.isRetrying = false
                    self.lastFailedAudioData = cachedAudio
                    let msg = "Still having trouble — tap here to retry or keep talking."
                    self.addBubble(ChatBubble(sender: .ai, text: msg))
                    self.isProcessing = false
                    self.restartListening()
                }
            }
        }
    }

    private func speakAI(audioData: Data) {
        guard !isMuted else {
            isProcessing = false
            restartListening()
            return
        }

        currentState = .speaking

        // Configure audio session BEFORE playing — the very first greeting
        // fires before startListening() ever runs, so the session may not
        // be set to .playAndRecord yet.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)

        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()

            guard audioPlayer?.play() == true else {
                print("⚠️ Audio player play() returned false")
                isProcessing = false
                restartListening()
                return
            }

            // Safety: if the delegate never fires (e.g. corrupted audio), force-start listening
            let safeDuration = (audioPlayer?.duration ?? 5.0) + 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + safeDuration) { [weak self] in
                guard let self, self.currentState == .speaking else { return }
                print("⚠️ Audio delegate timeout — forcing transition to listening")
                self.audioPlayer?.stop()
                self.isProcessing = false
                self.restartListening()
            }
        } catch {
            print("❌ Audio Player setup failed:", error)
            isProcessing = false
            restartListening()
        }
    }

    // MARK: - Button Actions

    @objc private func toggleMute(_ sender: UIButton) {
        isMuted.toggle()
        sender.setImage(
            UIImage(systemName: isMuted ? "mic.slash.fill" : "mic.fill",
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)),
            for: .normal
        )

        if isMuted {
            audioPlayer?.stop()
            teardownAudio()
            currentState = .idle
        } else {
            startListening()
        }
    }

    @objc private func closeTapped() {
        guard !isClosing else { return }
        isClosing = true
        muteButton.isEnabled = false
        closeButton.isEnabled = false
        displayLink?.invalidate()
        displayLink = nil

        audioPlayer?.stop()
        teardownAudio()

        let turnSummaries = sessionTurnSummaries
        sessionTurnSummaries = []

        let duration = Date().timeIntervalSince(callStartDate)
        guard duration > 1, let user = UserDataModel.shared.getCurrentUser() else {
            conversationHistory.removeAll()
            userTranscriptParts.removeAll()
            dismiss(animated: true)
            return
        }

        let userId = user.id

        // Persist call record to Supabase
        CallRecordDataModel.shared.logCall(
            userId: userId,
            duration: duration
        )

        // Mark session completed for streak/XP tracking
        SessionProgressManager.shared.markCompleted(
            .aiCall,
            topic: "Open Conversation",
            actualDurationMinutes: max(1, Int(duration) / 60)
        )

        // Build the full user transcript from preserved user turns.
        let fullTranscript = userTranscriptParts.joined(separator: " ")

        guard !fullTranscript.isEmpty || !turnSummaries.isEmpty else {
            conversationHistory.removeAll()
            userTranscriptParts.removeAll()
            dismiss(animated: true)
            return
        }

        // Get last audio data for session analysis
        let lastAudioData: Data? = {
            guard let url = AudioManager.shared.lastRecordingURL else { return nil }
            return try? Data(contentsOf: url)
        }()

        let sessionId = UUID().uuidString
        conversationHistory.removeAll()
        userTranscriptParts.removeAll()

        // Call the end-session endpoint for comprehensive feedback
        currentState = .processing
        Task {
            do {
                let response = try await BackendSpeechService.shared.endSession(
                    lastAudioData: lastAudioData,
                    fullTranscript: fullTranscript,
                    totalDurationS: duration,
                    userId: userId.uuidString,
                    sessionId: sessionId,
                    turnSummaries: turnSummaries,
                    mode: "call"
                )

                // Create SessionFeedback and log to history
                let sessionFeedback = BackendSpeechService.toSessionFeedback(
                    response,
                    sessionId: UUID(uuidString: sessionId) ?? UUID()
                )

                await MainActor.run {
                    HistoryDataModel.shared.logActivity(
                        type: .aiCall,
                        title: "AI Call",
                        topic: "Open Conversation",
                        duration: max(1, Int(duration) / 60),
                        imageURL: "Call",
                        xpEarned: 10,
                        isCompleted: true,
                        feedback: sessionFeedback
                    )

                    // Present feedback screen
                    let feedbackVC = FeedbackCollectionViewController()
                    feedbackVC.transcript = fullTranscript
                    feedbackVC.topic = "AI Call"
                    feedbackVC.speakingDuration = duration
                    feedbackVC.sessionId = sessionId
                    feedbackVC.userId = userId.uuidString

                    // Inject the pre-fetched response so FeedbackVC doesn't re-fetch
                    feedbackVC.preloadedResponse = response

                    let nav = UINavigationController(rootViewController: feedbackVC)
                    nav.modalPresentationStyle = .fullScreen
                    // Present feedback from the presenting VC so dismissing it
                    // doesn't land the user back on the dead call screen.
                    if let presenter = self.presentingViewController {
                        self.dismiss(animated: false) {
                            presenter.present(nav, animated: true)
                        }
                    } else {
                        self.present(nav, animated: true)
                    }
                }

            } catch {
                print("❌ End-session feedback failed: \(error.localizedDescription)")
                await MainActor.run {
                    // Build fallback feedback from locally-collected turn summaries
                    let fallbackFeedback = self.buildLocalFallbackFeedback(
                        turnSummaries: turnSummaries,
                        fullTranscript: fullTranscript,
                        duration: duration,
                        sessionId: sessionId
                    )

                    HistoryDataModel.shared.logActivity(
                        type: .aiCall,
                        title: "AI Call",
                        topic: "Open Conversation",
                        duration: max(1, Int(duration) / 60),
                        imageURL: "Call",
                        xpEarned: 10,
                        isCompleted: true,
                        feedback: fallbackFeedback
                    )

                    // Still show the feedback screen with locally-computed data
                    let fallbackResponse = self.buildLocalFallbackResponse(
                        turnSummaries: turnSummaries,
                        fullTranscript: fullTranscript,
                        duration: duration
                    )

                    let feedbackVC = FeedbackCollectionViewController()
                    feedbackVC.transcript = fullTranscript
                    feedbackVC.topic = "AI Call"
                    feedbackVC.speakingDuration = duration
                    feedbackVC.sessionId = sessionId
                    feedbackVC.userId = userId.uuidString
                    feedbackVC.preloadedResponse = fallbackResponse

                    let nav = UINavigationController(rootViewController: feedbackVC)
                    nav.modalPresentationStyle = .fullScreen
                    if let presenter = self.presentingViewController {
                        self.dismiss(animated: false) {
                            presenter.present(nav, animated: true)
                        }
                    } else {
                        self.present(nav, animated: true)
                    }
                }
            }
        }
    }

    // MARK: - Local Fallback Helpers

    /// Build a SessionFeedback from locally-collected turn summaries when the backend is unreachable.
    private func buildLocalFallbackFeedback(
        turnSummaries: [SessionTurnSummary],
        fullTranscript: String,
        duration: TimeInterval,
        sessionId: String
    ) -> SessionFeedback {
        let totalFillers = turnSummaries.reduce(0) { $0 + $1.fillers }
        let totalPauses = turnSummaries.reduce(0) { $0 + $1.pauses }
        let totalWords = turnSummaries.reduce(0) { $0 + $1.totalWords }
        let wpm = duration > 0 ? Double(totalWords) / (duration / 60.0) : 0
        let fluency = max(0, min(100, 85 - Double(totalFillers) * 3 - Double(totalPauses) * 2))

        return SessionFeedback(
            id: UUID().uuidString,
            sessionId: UUID(uuidString: sessionId) ?? UUID(),
            fillerWordCount: totalFillers,
            mispronouncedWords: [],
            fluencyScore: fluency,
            onTopicScore: max(50, fluency - 5),
            pauses: totalPauses,
            summary: "Session completed (\(turnSummaries.count) turns, \(Int(wpm)) WPM). Feedback computed locally.",
            createdAt: Date()
        )
    }

    /// Build a SpeechAnalysisResponse from locally-collected turn summaries for the feedback screen.
    private func buildLocalFallbackResponse(
        turnSummaries: [SessionTurnSummary],
        fullTranscript: String,
        duration: TimeInterval
    ) -> SpeechAnalysisResponse {
        let totalWords = turnSummaries.reduce(0) { $0 + $1.totalWords }
        let totalFillers = turnSummaries.reduce(0) { $0 + $1.fillers }
        let totalPauses = turnSummaries.reduce(0) { $0 + $1.pauses }
        let totalVeryLongPauses = turnSummaries.reduce(0) { $0 + $1.veryLongPauses }
        let totalRepetitions = turnSummaries.reduce(0) { $0 + $1.repetitions }
        let durationS = duration > 0 ? duration : 30.0
        let wpm = durationS > 0 ? Double(totalWords) / (durationS / 60.0) : 0
        let fillerRate = durationS > 0 ? Double(totalFillers) / durationS * 60.0 : 0
        let avgPause: Double = {
            let pauseTurns = turnSummaries.filter { $0.pauses > 0 }
            guard !pauseTurns.isEmpty else { return 0 }
            return pauseTurns.reduce(0.0) { $0 + $1.avgPauseS } / Double(pauseTurns.count)
        }()

        let metrics = SpeechMetrics(
            wpm: wpm,
            totalWords: totalWords,
            durationS: durationS,
            fillerRatePerMin: fillerRate,
            fillers: totalFillers,
            pauses: totalPauses,
            avgPauseS: avgPause,
            veryLongPauses: totalVeryLongPauses,
            repetitions: totalRepetitions,
            fillerExamples: [],
            pauseExamples: []
        )

        let fluency = max(0, min(100, 85 - Double(totalFillers) * 3 - Double(totalRepetitions) * 5))
        let confidence = max(0, min(100, wpm >= 100 && wpm <= 170 ? 80 : 60))
        let clarity = max(0, min(100, 80 - Double(totalVeryLongPauses) * 5 - Double(totalRepetitions) * 4))

        let coaching = SpeechCoaching(
            scores: CoachingScores(fluency: fluency, confidence: Double(confidence), clarity: clarity),
            primaryIssue: totalFillers > 5 ? "Reduce filler words to improve fluency." : "Keep practising for smoother speech.",
            primaryIssueTitle: totalFillers > 5 ? "Filler Words" : "General Practice",
            secondaryIssues: [],
            strengths: totalWords > 50 ? ["Good amount of speaking"] : [],
            suggestions: ["Try to reduce filler words", "Practice speaking at a steady pace"],
            evidence: [],
            llmCoaching: nil
        )

        let progress = SpeechProgress(
            deltas: Deltas(wpm: 0, fillers: 0, pauses: 0),
            overallDirection: "mixed",
            weeklySummary: "Session completed (offline feedback)."
        )

        return SpeechAnalysisResponse(
            transcript: fullTranscript,
            metrics: metrics,
            coaching: coaching,
            progress: progress
        )
    }
}

// MARK: - AVAudioPlayerDelegate

extension AICallController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Transition from speaking → listening.
        // Reset state first so restartListening's guards pass.
        currentState = .idle
        isProcessing = false
        restartListening()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension AICallController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chatBubbles.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatBubbleCell.id, for: indexPath) as! ChatBubbleCell
        let bubble = chatBubbles[indexPath.row]
        cell.configure(text: bubble.text, isUser: bubble.sender == .user)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let bubble = chatBubbles[indexPath.row]
        if bubble.sender == .ai, bubble.text.contains("tap here to retry"), lastFailedAudioData != nil {
            retryLastTurn()
        }
    }
}

// MARK: - Chat Bubble Cell

private final class ChatBubbleCell: UITableViewCell {

    static let id = "ChatBubbleCell"

    private let bubbleView: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 16
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .regular)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let senderLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(senderLabel)
        contentView.addSubview(bubbleView)
        bubbleView.addSubview(messageLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            senderLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            senderLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            senderLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            bubbleView.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.78),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, isUser: Bool) {
        messageLabel.text = text

        // Deactivate both, then activate the correct one
        leadingConstraint.isActive = false
        trailingConstraint.isActive = false

        if isUser {
            trailingConstraint.isActive = true
            bubbleView.backgroundColor = AppColors.primary
            messageLabel.textColor = .white
            senderLabel.text = "You"
            senderLabel.textColor = AppColors.primary
            senderLabel.textAlignment = .right
        } else {
            leadingConstraint.isActive = true
            bubbleView.backgroundColor = AppColors.cardBackground
            bubbleView.layer.borderColor = AppColors.cardBorder.cgColor
            bubbleView.layer.borderWidth = 1
            messageLabel.textColor = AppColors.textPrimary
            senderLabel.text = "AI"
            senderLabel.textColor = .secondaryLabel
            senderLabel.textAlignment = .left
        }
    }
}

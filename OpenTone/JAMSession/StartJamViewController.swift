import UIKit
import Speech
import AVFoundation

class StartJamViewController: UIViewController {

    @IBOutlet weak var timerRingView: TimerRingView!
    @IBOutlet weak var timerLabel: UILabel!
    @IBOutlet weak var topicHeaderLabel: UILabel!
    @IBOutlet weak var topicTitleLabel: UILabel!
    @IBOutlet weak var hintButton: UIButton!
    @IBOutlet weak var bottomActionStackView: UIStackView!

    @IBOutlet var micButton: UIButton!

    private let timerManager = TimerManager(totalSeconds: 30)
    private var remainingSeconds: Int = 30
    private var hintStackView: UIStackView?
    private var didFinishSpeech = false
    private var isMicOn = false
    private var pulseLayer: CAShapeLayer?

    // MARK: - Speech Recognition

    private let audioEngine = AVAudioEngine()

    /// Tracks whether recording has been started at least once.
    private var hasStartedRecording = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        timerManager.delegate = self
        navigationItem.hidesBackButton = true

        // Load topic from active session
        if let session = JamSessionDataModel.shared.getActiveSession() {
            topicTitleLabel.text = session.topic
            remainingSeconds = 30  // Speaking always gets full 30 seconds
        }

        // Mark the speaking phase in the data model
        JamSessionDataModel.shared.beginSpeakingPhase()

        // Add an invisible spacer to balance the stack: [hint] [mic] [spacer]
        // This keeps the mic button centered.
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.isUserInteractionEnabled = false
        bottomActionStackView.addArrangedSubview(spacer)
        NSLayoutConstraint.activate([
            spacer.widthAnchor.constraint(equalToConstant: 50),
            spacer.heightAnchor.constraint(equalToConstant: 50),
        ])

        applyDarkModeStyles()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: StartJamViewController, _) in
            self.applyDarkModeStyles()
        }

        // Request microphone permissions, then start recording
        requestMicrophonePermissions()
    }

    private func applyDarkModeStyles() {
        view.backgroundColor = AppColors.screenBackground
        timerRingView.superview?.backgroundColor = AppColors.screenBackground
        timerRingView.backgroundColor = AppColors.screenBackground
        topicTitleLabel.textColor = AppColors.textPrimary
        topicHeaderLabel?.textColor = AppColors.primary
        timerLabel.textColor = AppColors.textPrimary

        let isDark = traitCollection.userInterfaceStyle == .dark
        let buttonBg = isDark
            ? UIColor.tertiarySystemGroupedBackground
            : AppColors.primaryLight

        for case let button as UIButton in bottomActionStackView.arrangedSubviews {
            if var config = button.configuration {
                config.background.backgroundColor = buttonBg
                button.configuration = config
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.tabBar.isHidden = true
        timerLabel.text = format(remainingSeconds)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        timerManager.reset()
        timerRingView.resetRing()
        timerRingView.animateRing(
            remainingSeconds: remainingSeconds,
            totalSeconds: 30
        )
        timerManager.start(from: remainingSeconds)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timerManager.reset()
        // Stop and clean up before leaving
        stopRecording()
        stopPulseAnimation()

        guard var session = JamSessionDataModel.shared.getActiveSession() else { return }
        session.secondsLeft = remainingSeconds
        JamSessionDataModel.shared.updateActiveSession(session)
    }

    // MARK: - Navigation

    @objc private func backButtonTapped() {
        showExitAlert()
    }

    private func showExitAlert() {
        timerManager.pause()
        pauseRecording()
        timerRingView.resetRing()
        timerRingView.setProgress(value: CGFloat(remainingSeconds), max: 30) // Pause visual state

        let alert = UIAlertController(
            title: "Exit Session",
            message: "Would you like to save this session for later or exit without saving?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            // Resume the timer and recording
            self.timerManager.start(from: self.remainingSeconds)
            self.timerRingView.animateRing(
                remainingSeconds: self.remainingSeconds,
                totalSeconds: 30
            )
            // Start a fresh recognition session (Apple requires new sessions)
            self.startRecording()
        })

        alert.addAction(UIAlertAction(title: "Save & Exit", style: .default) { _ in
            if var session = JamSessionDataModel.shared.getActiveSession() {
                session.secondsLeft = self.remainingSeconds
                JamSessionDataModel.shared.updateActiveSession(session)
            }
            JamSessionDataModel.shared.saveSessionForLater()
            self.navigateBackToRoot()
        })

        alert.addAction(UIAlertAction(title: "Exit", style: .destructive) { _ in
            JamSessionDataModel.shared.cancelJamSession()
            self.navigateBackToRoot()
        })

        present(alert, animated: true)
    }

    private func navigateBackToRoot() {
        tabBarController?.tabBar.isHidden = false
        navigationController?.popToRootViewController(animated: true)
    }

    // MARK: - Actions

    @IBAction func micTapped(_ sender: UIButton) {
        isMicOn.toggle()
        if isMicOn {
            startRecording()
        } else {
            pauseRecording()
        }
        updateMicButtonState()
    }

    /// Single source of truth for mic button visuals + animation.
    /// Works with UIButton.Configuration (set in storyboard).
    private func updateMicButtonState() {
        guard var config = micButton.configuration else { return }

        let isActive = isMicOn
        let imageName = isActive ? "mic.fill" : "mic.slash.fill"
        let tint: UIColor  = isActive ? AppColors.primary : .systemRed
        let bg: UIColor    = isActive ? AppColors.primaryLight : UIColor.systemRed.withAlphaComponent(0.12)
        let border: UIColor = isActive ? AppColors.primary : .systemRed

        config.image = UIImage(systemName: imageName)?
            .withConfiguration(UIImage.SymbolConfiguration(scale: .large))
        config.baseForegroundColor = tint
        config.background.backgroundColor = bg
        config.background.strokeColor = border
        config.background.strokeWidth = isActive ? 3 : 1
        micButton.configuration = config

        // Pulse animation
        if isActive {
            startPulseAnimation()
        } else {
            stopPulseAnimation()
        }
    }

    // MARK: - Pulse Animation

    private func startPulseAnimation() {
        stopPulseAnimation()

        let diameter = micButton.bounds.width + 24
        let pulse = CAShapeLayer()
        let circularPath = UIBezierPath(
            arcCenter: CGPoint(x: micButton.bounds.midX, y: micButton.bounds.midY),
            radius: diameter / 2,
            startAngle: 0,
            endAngle: 2 * .pi,
            clockwise: true
        )
        pulse.path = circularPath.cgPath
        pulse.fillColor = AppColors.primary.withAlphaComponent(0.25).cgColor
        pulse.opacity = 0

        micButton.layer.insertSublayer(pulse, at: 0)
        pulseLayer = pulse

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.85
        scaleAnim.toValue   = 1.15

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.6
        opacityAnim.toValue   = 0.0

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration     = 1.2
        group.repeatCount  = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)

        pulse.add(group, forKey: "pulse")
    }

    private func stopPulseAnimation() {
        pulseLayer?.removeAllAnimations()
        pulseLayer?.removeFromSuperlayer()
        pulseLayer = nil
    }

    @IBAction func hintTapped(_ sender: UIButton) {
        hintStackView == nil ? showHints() : removeHints()
    }

    private func showHints() {
        removeHints()

        let hints = JamSessionDataModel.shared.generateSpeakingHints()

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        view.addSubview(stack)
        view.bringSubviewToFront(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: bottomActionStackView.topAnchor, constant: -15),
            stack.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8)
        ])

        hintStackView = stack
        hints.forEach { stack.addArrangedSubview(createHintChip(text: $0)) }
    }

    private func createHintChip(text: String) -> UIView {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let chip = UIView()
        chip.backgroundColor = isDark
            ? AppColors.primary.withAlphaComponent(0.20)
            : AppColors.primary.withAlphaComponent(0.12)
        chip.layer.cornerRadius = 22
        chip.layer.borderWidth = 2
        chip.layer.borderColor = AppColors.primary.cgColor

        let label = UILabel()
        label.text = text
        label.textColor = AppColors.textPrimary
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.numberOfLines = 0

        chip.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -12),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -16)
        ])

        return chip
    }

    private func removeHints() {
        hintStackView?.removeFromSuperview()
        hintStackView = nil
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Audio Recording

    private func requestMicrophonePermissions() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        print("⚠️ Microphone permission denied")
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startRecording()
                    } else {
                        print("⚠️ Microphone permission denied")
                    }
                }
            }
        }
    }

    private func startRecording() {
        // We now rely exclusively on AudioManager for the actual file recording
        // rather than starting our own engine, since we ripped out SFSpeechRecognizer
        AudioManager.shared.startRecording()
        hasStartedRecording = true
        isMicOn = true
        updateMicButtonState()
    }

    private func pauseRecording() {
        AudioManager.shared.stopRecording()
    }

    private func stopRecording() {
        AudioManager.shared.stopRecording()
    }



}

// MARK: - TimerManagerDelegate

extension StartJamViewController: TimerManagerDelegate {

    func timerManagerDidStartMainTimer() {}

    func timerManagerDidUpdateMainTimer(_ formattedTime: String) {
        timerLabel.text = formattedTime

        let parts = formattedTime.split(separator: ":")
        if parts.count == 2,
           let min = Int(parts[0]),
           let sec = Int(parts[1]) {
            remainingSeconds = min * 60 + sec
        }
    }

    func timerManagerDidFinish() {
        guard !didFinishSpeech else { return }
        didFinishSpeech = true

        // Note: The feedback screen uploads the audio file to Whisper via /analyze/audio
        // to get the transcript, metrics, and coaching.
        stopRecording()
        stopPulseAnimation()

        timerLabel.text = "00:00"

        guard var session = JamSessionDataModel.shared.getActiveSession() else { return }
        session.phase = .completed
        session.endedAt = Date()
        JamSessionDataModel.shared.updateActiveSession(session)

        // Calculate speaking duration
        let speakingDuration: Double
        if let start = session.startedSpeakingAt {
            speakingDuration = Date().timeIntervalSince(start)
        } else {
            speakingDuration = 30.0
        }
          
        let vc = FeedbackCollectionViewController()
        vc.transcript       = nil
        vc.topic            = session.topic
        vc.speakingDuration = speakingDuration
        vc.sessionId        = session.id.uuidString
        vc.userId           = UserDataModel.shared.getCurrentUser()?.id.uuidString ?? "demo"
        
        // Pass the raw local audio file to the feedback screen to unlock Whisper timestamps
        if let localURL = AudioManager.shared.lastRecordingURL {
            vc.audioURL = localURL.absoluteString
        }
        tabBarController?.tabBar.isHidden = false
        navigationController?.pushViewController(vc, animated: true)
    }
}


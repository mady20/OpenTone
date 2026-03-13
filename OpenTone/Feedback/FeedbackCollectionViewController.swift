//
//  FeedbackCollectionViewController.swift
//  OpenTone
//
//  Created by M S on 26/02/26.
//  Rebuilt: Phase 1 — real feedback screen backed by BackendSpeechService.
//

import UIKit

// MARK: - Section model

private enum FeedbackSection: Int, CaseIterable {
    case loading = 0   // spinner while we wait for the backend
    case scores        // overall / fluency / confidence / clarity rings
    case metrics       // WPM, fillers, pauses, etc.
    case coaching      // primary issue + suggestions
    case transcript    // transcript with filler / pause highlights
    case progress      // deltas vs. previous session
}

private let scoreCellId      = "ScoreCell"
private let metricCellId     = "MetricCell"
private let coachingCellId   = "CoachingCell"
private let progressCellId   = "ProgressCell"
private let loadingCellId    = "LoadingCell"
private let headerKind       = UICollectionView.elementKindSectionHeader
private let headerReuseId    = "FeedbackHeader"

// MARK: - Controller

class FeedbackCollectionViewController: UIViewController {

    // ---- Public properties set by the pushing screen (StartJamVC) ----------

    var transcript: String?
    var topic: String?
    var speakingDuration: Double = 30
    var sessionId: String = ""
    var userId: String = "demo"
    var audioURL: String?          // local file:// or remote URL

    /// Pre-fetched response — if set, the VC skips its own network call.
    /// Used by AI Call and Roleplay to inject the already-fetched analysis.
    var preloadedResponse: SpeechAnalysisResponse?

    // ---- Private state -----------------------------------------------------

    private var feedback: Feedback?
    private var analysisResponse: SpeechAnalysisResponse?
    private var isLoading = true
    private var errorMessage: String?

    private var collectionView: UICollectionView!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Session Feedback"
        view.backgroundColor = AppColors.screenBackground
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped)
        )

        configureCollectionView()
        fetchAnalysis()
    }

    // MARK: - Layout

    private func configureCollectionView() {
        let layout = createLayout()
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = AppColors.screenBackground
        collectionView.dataSource = self
        collectionView.delegate = self

        // Register cells
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: loadingCellId)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: scoreCellId)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: metricCellId)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: coachingCellId)
        collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: progressCellId)
        collectionView.register(
            UICollectionReusableView.self,
            forSupplementaryViewOfKind: headerKind,
            withReuseIdentifier: headerReuseId
        )

        view.addSubview(collectionView)
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        return UICollectionViewCompositionalLayout { [weak self] sectionIndex, env in
            let section: FeedbackSection
            if self?.isLoading == true || self?.errorMessage != nil {
                section = .loading
            } else {
                section = FeedbackSection(rawValue: sectionIndex + 1) ?? .scores
            }
            switch section {
            case .loading:      return Self.listSection()
            case .scores:       return Self.scoreGridSection()
            case .metrics:      return Self.listSection()
            case .coaching:     return Self.listSection()
            case .transcript:   return Self.listSection()
            case .progress:     return Self.listSection()
            }
        }
    }

    private static func listSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(56))
        )
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(56)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 16, bottom: 16, trailing: 16)
        section.interGroupSpacing = 8
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private static func scoreGridSection() -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(
            layoutSize: .init(widthDimension: .fractionalWidth(0.5), heightDimension: .estimated(100))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100)),
            subitems: [item, item]
        )
        group.interItemSpacing = .fixed(12)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 8, leading: 16, bottom: 16, trailing: 16)
        section.interGroupSpacing = 12
        section.boundarySupplementaryItems = [headerItem()]
        return section
    }

    private static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        return .init(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(36)),
            elementKind: headerKind,
            alignment: .top
        )
    }

    // MARK: - Network

    private func fetchAnalysis() {
        // If the caller already provided an analysis, don't refetch
        if let preloaded = analysisResponse {
            self.analysisResponse = preloaded
            self.feedback = BackendSpeechService.toFeedback(preloaded)
            self.isLoading = false
            self.collectionView.reloadData()
            return
        }

        Task {
            do {
                let response: SpeechAnalysisResponse

                // Prefer extracting transcription locally
                if let urlString = audioURL,
                   let fileURL = URL(string: urlString),
                   FileManager.default.fileExists(atPath: fileURL.path) {
                    
                    self.transcript = await withCheckedContinuation { continuation in
                        AudioManager.shared.transcribeFile(at: fileURL) { text in
                            continuation.resume(returning: text ?? "")
                        }
                    }
                    
                    response = try await BackendSpeechService.shared.analyzeAudio(
                        transcript: self.transcript!,
                        durationS: speakingDuration > 0 ? speakingDuration : 30.0,
                        userId:    userId,
                        sessionId: sessionId
                    )
                } else {
                    // Fallback to text-only /analyze
                    response = try await BackendSpeechService.shared.analyze(
                        audioURL:   audioURL,
                        transcript: transcript,
                        durationS:  speakingDuration,
                        userId:     userId,
                        sessionId:  sessionId
                    )
                }

                self.analysisResponse = response
                self.feedback = BackendSpeechService.toFeedback(response)
                self.isLoading = false
                await MainActor.run {
                    self.collectionView.reloadData()
                }
                self.persistFeedbackToHistory(response)

            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                await MainActor.run {
                    self.collectionView.reloadData()
                }
            }
        }
    }

    /// Persist the analysis result as a SessionFeedback on the most recent matching activity.
    private func persistFeedbackToHistory(_ response: SpeechAnalysisResponse) {
        let sid = UUID(uuidString: sessionId) ?? UUID()
        let sessionFeedback = BackendSpeechService.toSessionFeedback(response, sessionId: sid)

        // Attach to the Jam activity that was already logged (without feedback)
        HistoryDataModel.shared.attachFeedbackToLatestActivity(
            type: .jam,
            feedback: sessionFeedback
        )
    }

    // MARK: - Actions

    @objc private func doneTapped() {
        // If presented modally (e.g. from AI Call), dismiss the entire nav stack
        if presentingViewController != nil || navigationController?.presentingViewController != nil {
            dismiss(animated: true)
        } else {
            // Pushed on a navigation stack (e.g. from Jam session)
            navigationController?.popToRootViewController(animated: true)
        }
    }

    // MARK: - Cell helpers

    private func makeCard(_ cell: UICollectionViewCell) {
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        cell.contentView.backgroundColor = AppColors.cardBackground
        cell.contentView.layer.cornerRadius = 14
        cell.contentView.clipsToBounds = true
    }

    private func addLabel(to cell: UICollectionViewCell, text: String, font: UIFont = .systemFont(ofSize: 15),
                          color: UIColor = .label, lines: Int = 0, insets: UIEdgeInsets = .init(top: 12, left: 14, bottom: 12, right: 14)) {
        let lbl = UILabel()
        lbl.text = text
        lbl.font = font
        lbl.textColor = color
        lbl.numberOfLines = lines
        lbl.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: insets.top),
            lbl.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: insets.left),
            lbl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -insets.right),
            lbl.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -insets.bottom),
        ])
    }

    private func addAttributedLabel(to cell: UICollectionViewCell,
                                    attributedText: NSAttributedString,
                                    insets: UIEdgeInsets = .init(top: 12, left: 14, bottom: 12, right: 14)) {
        let lbl = UILabel()
        lbl.attributedText = attributedText
        lbl.numberOfLines = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: insets.top),
            lbl.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: insets.left),
            lbl.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -insets.right),
            lbl.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -insets.bottom),
        ])
    }

    private func coachingSuggestions(from response: SpeechAnalysisResponse, feedback: Feedback) -> [String] {
        let llmSuggestions = response.coaching.llmCoaching?.suggestions ?? []
        if !llmSuggestions.isEmpty {
            return Array(llmSuggestions.prefix(4))
        }
        return Array((feedback.coaching?.suggestions ?? []).prefix(4))
    }

    private func coachingFocus(from response: SpeechAnalysisResponse, feedback: Feedback) -> String {
        let llmPrimary = response.coaching.llmCoaching?.primaryIssue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !llmPrimary.isEmpty {
            return llmPrimary
        }
        return feedback.coaching?.primaryIssueTitle ?? "Good job!"
    }

    private func transcriptSummary(from response: SpeechAnalysisResponse) -> String? {
        var parts: [String] = []

        if !response.metrics.fillerExamples.isEmpty {
            let fillerText = response.metrics.fillerExamples.prefix(5).map {
                "• \($0.word) at \(timestampString($0.timestamp))"
            }.joined(separator: "\n")
            parts.append("Filler words\n\(fillerText)")
        }

        if !response.metrics.pauseExamples.isEmpty {
            let pauseText = response.metrics.pauseExamples.prefix(5).map {
                "• \(timestampString($0.start)) for \(String(format: "%.1f", $0.duration))s"
            }.joined(separator: "\n")
            parts.append("Long pauses\n\(pauseText)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private func timestampString(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func transcriptWithPauseMarkers(from response: SpeechAnalysisResponse) -> String {
        let transcript = response.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return "No transcript available." }

        let words = transcript.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return transcript }

        let totalDuration = max(response.metrics.durationS, 0.1)
        var insertions: [Int: [String]] = [:]

        for pause in response.metrics.pauseExamples.prefix(5) {
            let ratio = min(max(pause.start / totalDuration, 0), 1)
            let rawIndex = Int((Double(words.count) * ratio).rounded())
            let insertionIndex = min(max(rawIndex, 1), words.count)
            let marker = "⏸ \(String(format: "%.1f", pause.duration))s pause"
            insertions[insertionIndex, default: []].append(marker)
        }

        var rendered: [String] = []
        for (index, word) in words.enumerated() {
            if let markers = insertions[index], !markers.isEmpty {
                rendered.append(contentsOf: markers)
            }
            rendered.append(word)
        }

        if let tailMarkers = insertions[words.count], !tailMarkers.isEmpty {
            rendered.append(contentsOf: tailMarkers)
        }

        return rendered.joined(separator: " ")
    }

    private func highlightedTranscript(from response: SpeechAnalysisResponse) -> NSAttributedString {
        let displayText = transcriptWithPauseMarkers(from: response)
        let attributed = NSMutableAttributedString(
            string: displayText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor.label,
            ]
        )

        let fullRange = NSRange(location: 0, length: (displayText as NSString).length)
        let pausePattern = "⏸\\s[0-9.]+s\\spause"
        if let regex = try? NSRegularExpression(pattern: pausePattern, options: []) {
            regex.matches(in: displayText, options: [], range: fullRange).forEach { match in
                attributed.addAttributes([
                    .foregroundColor: UIColor.systemBlue,
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                ], range: match.range)
            }
        }

        let fillerWords = Set(response.metrics.fillerExamples.map { $0.word.lowercased() })
        for filler in fillerWords where !filler.isEmpty {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            regex.matches(in: displayText, options: [], range: fullRange).forEach { match in
                attributed.addAttributes([
                    .foregroundColor: UIColor.systemOrange,
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .backgroundColor: UIColor.systemOrange.withAlphaComponent(0.18),
                ], range: match.range)
            }
        }

        return attributed
    }

    private func scoreCard(_ cell: UICollectionViewCell, title: String, value: Double) {
        makeCard(cell)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -8),
        ])

        let numLabel = UILabel()
        numLabel.text = String(format: "%.0f", value)
        numLabel.font = .systemFont(ofSize: 28, weight: .bold)
        numLabel.textColor = AppColors.primary

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .secondaryLabel

        stack.addArrangedSubview(numLabel)
        stack.addArrangedSubview(titleLabel)
    }
}

// MARK: - UICollectionViewDataSource

extension FeedbackCollectionViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if isLoading || errorMessage != nil { return 1 }     // loading / error
        guard feedback != nil else { return 1 }
        return FeedbackSection.allCases.count - 1            // skip .loading section
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isLoading { return 1 }
        if errorMessage != nil { return 1 }

        // Map displayed section back (we skip .loading when data is ready)
        let mapped = FeedbackSection(rawValue: section + 1) ?? .scores
        guard let fb = feedback, let resp = analysisResponse else { return 0 }

        switch mapped {
        case .loading:       return 0
        case .scores:        return 4   // overall, fluency, confidence, clarity
        case .metrics:       return 4   // WPM, fillers, pauses, duration
        case .coaching:      return 1 + coachingSuggestions(from: resp, feedback: fb).count
        case .transcript:    return transcriptSummary(from: resp) == nil ? 1 : 2
        case .progress:      return 1   // deltas card
        }
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        // --- Loading / error state ---
        if isLoading {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: loadingCellId, for: indexPath)
            cell.contentView.subviews.forEach { $0.removeFromSuperview() }
            let spinner = UIActivityIndicatorView(style: .large)
            spinner.startAnimating()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                spinner.heightAnchor.constraint(equalToConstant: 80),
            ])
            return cell
        }
        if let err = errorMessage {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: loadingCellId, for: indexPath)
            makeCard(cell)
            addLabel(to: cell, text: "⚠️ \(err)", font: .systemFont(ofSize: 14), color: .systemRed)
            return cell
        }

        guard let fb = feedback, let resp = analysisResponse else {
            return cv.dequeueReusableCell(withReuseIdentifier: loadingCellId, for: indexPath)
        }

        let mapped = FeedbackSection(rawValue: indexPath.section + 1) ?? .scores

        switch mapped {

        // --- Scores (2×2 grid) ---
        case .scores:
            let cell = cv.dequeueReusableCell(withReuseIdentifier: scoreCellId, for: indexPath)
            let titles = ["Overall", "Fluency", "Confidence", "Clarity"]
            let values: [Double] = [
                fb.coaching?.scores.overall ?? 0,
                fb.coaching?.scores.fluency ?? 0,
                fb.coaching?.scores.confidence ?? 0,
                fb.coaching?.scores.clarity ?? 0,
            ]
            scoreCard(cell, title: titles[indexPath.item], value: values[indexPath.item])
            return cell

        // --- Metrics ---
        case .metrics:
            let cell = cv.dequeueReusableCell(withReuseIdentifier: metricCellId, for: indexPath)
            makeCard(cell)
            let labels = [
                "🗣  \(Int(fb.wordsPerMinute)) WPM",
                "😬  \(fb.fillerWordCount ?? 0) filler words",
                "⏸  \(fb.pauseCount ?? 0) long pauses",
                "⏱  \(String(format: "%.0f", fb.durationInSeconds))s spoken",
            ]
            addLabel(to: cell, text: labels[indexPath.item], font: .systemFont(ofSize: 15, weight: .medium))
            return cell

        // --- Coaching ---
        case .coaching:
            let cell = cv.dequeueReusableCell(withReuseIdentifier: coachingCellId, for: indexPath)
            makeCard(cell)
            let suggestions = coachingSuggestions(from: resp, feedback: fb)
            if indexPath.item == 0 {
                // Primary issue header
                let issue = coachingFocus(from: resp, feedback: fb)
                addLabel(to: cell, text: "🎯 Focus: \(issue)", font: .systemFont(ofSize: 16, weight: .semibold), color: AppColors.primary)
            } else {
                // Suggestion
                let idx = indexPath.item - 1
                let text = idx < suggestions.count ? "💡 \(suggestions[idx])" : ""
                addLabel(to: cell, text: text, font: .systemFont(ofSize: 14))
            }
            return cell

        // --- Transcript ---
        case .transcript:
            let cell = cv.dequeueReusableCell(withReuseIdentifier: coachingCellId, for: indexPath)
            makeCard(cell)
            if indexPath.item == 0 {
                addAttributedLabel(to: cell, attributedText: highlightedTranscript(from: resp))
            } else {
                addLabel(
                    to: cell,
                    text: transcriptSummary(from: resp) ?? "No filler words or long pauses detected.",
                    font: .systemFont(ofSize: 14),
                    color: .secondaryLabel
                )
            }
            return cell

        // --- Progress deltas ---
        case .progress:
            let cell = cv.dequeueReusableCell(withReuseIdentifier: progressCellId, for: indexPath)
            makeCard(cell)
            let prog = resp.progress
            var parts: [String] = []
            if let w = prog.deltas.wpmDescription      { parts.append(w) }
            if let f = prog.deltas.fillersDescription   { parts.append(f) }
            let arrow = prog.directionArrow
            let summary = parts.isEmpty ? "First session — baseline set!" : parts.joined(separator: "\n")
            addLabel(to: cell, text: "\(arrow) \(prog.weeklySummary)\n\n\(summary)", font: .systemFont(ofSize: 14))
            return cell

        default:
            return cv.dequeueReusableCell(withReuseIdentifier: loadingCellId, for: indexPath)
        }
    }

    func collectionView(_ cv: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = cv.dequeueReusableSupplementaryView(
            ofKind: kind, withReuseIdentifier: headerReuseId, for: indexPath
        )
        header.subviews.forEach { $0.removeFromSuperview() }

        if isLoading || errorMessage != nil {
            return header  // no header during loading
        }

        let mapped = FeedbackSection(rawValue: indexPath.section + 1) ?? .scores
        let titles: [FeedbackSection: String] = [
            .scores: "Scores", .metrics: "Metrics", .coaching: "Coaching",
            .transcript: "Transcript",
            .progress: "Your Progress",
        ]

        let lbl = UILabel()
        lbl.text = titles[mapped] ?? ""
        lbl.font = .systemFont(ofSize: 18, weight: .bold)
        lbl.textColor = .label
        lbl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            lbl.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -4),
        ])

        return header
    }
}

// MARK: - UICollectionViewDelegate

extension FeedbackCollectionViewController: UICollectionViewDelegate {}

// MARK: - Safe subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

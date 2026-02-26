import UIKit

class ProgressHeaderView: UIView {

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Your Progress"
        lbl.font = .systemFont(ofSize: 22, weight: .bold)
        lbl.textColor = AppColors.textPrimary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let subtitleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Lifetime averages and recent trend"
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.textColor = .secondaryLabel
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    // Stats area
    private let statsStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 12
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // Trend area
    private let trendContainer: UIView = {
        let v = UIView()
        v.backgroundColor = AppColors.cardBackground
        v.layer.cornerRadius = 16
        v.layer.borderWidth = 1
        v.layer.borderColor = AppColors.cardBorder.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    
    private let trendLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Recent Scores"
        lbl.font = .systemFont(ofSize: 14, weight: .semibold)
        lbl.textColor = AppColors.textPrimary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let barChartStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .equalCentering
        sv.alignment = .bottom
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(statsStack)
        addSubview(trendContainer)

        trendContainer.addSubview(trendLabel)
        trendContainer.addSubview(barChartStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            statsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            statsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            statsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            trendContainer.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 16),
            trendContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            trendContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            trendContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            trendContainer.heightAnchor.constraint(equalToConstant: 120),

            trendLabel.topAnchor.constraint(equalTo: trendContainer.topAnchor, constant: 12),
            trendLabel.leadingAnchor.constraint(equalTo: trendContainer.leadingAnchor, constant: 16),

            barChartStack.leadingAnchor.constraint(equalTo: trendContainer.leadingAnchor, constant: 16),
            barChartStack.trailingAnchor.constraint(equalTo: trendContainer.trailingAnchor, constant: -16),
            barChartStack.bottomAnchor.constraint(equalTo: trendContainer.bottomAnchor, constant: -16),
            barChartStack.topAnchor.constraint(equalTo: trendLabel.bottomAnchor, constant: 16)
        ])
    }

    func configure(with profile: UserSpeechProfile) {
        // Clear old ones
        statsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        barChartStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Create Stat Cards
        let wpmCard = createStatCard(title: "WPM", value: String(format: "%.0f", profile.avgWpm))
        let fluCard = createStatCard(title: "Fluency", value: String(format: "%.0f", profile.overallScore))
        let filCard = createStatCard(title: "Fillers", value: String(format: "%.1f/m", profile.avgFillerRate))

        statsStack.addArrangedSubview(wpmCard)
        statsStack.addArrangedSubview(fluCard)
        statsStack.addArrangedSubview(filCard)

        // Create Trend Bars (max 7)
        let scores = profile.recentScores ?? []
        if scores.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "Complete your first session to see trend."
            emptyLabel.textColor = .tertiaryLabel
            emptyLabel.font = .systemFont(ofSize: 13)
            barChartStack.addArrangedSubview(emptyLabel)
            return
        }

        // Draw up to 7 bars
        // Scores are 0-100.
        let maxDisplayLines = 7
        let displayScores = Array(scores.suffix(maxDisplayLines))
        
        for score in displayScores {
            let barContainer = UIView()
            barContainer.translatesAutoresizingMaskIntoConstraints = false
            barContainer.widthAnchor.constraint(equalToConstant: 24).isActive = true
            
            let fillView = UIView()
            fillView.backgroundColor = AppColors.primary
            fillView.layer.cornerRadius = 4
            fillView.translatesAutoresizingMaskIntoConstraints = false
            
            barContainer.addSubview(fillView)
            
            // Height proportional to score (0-100) -> percentage of parent height
            let heightMultiplier = CGFloat(max(10, score)) / 100.0 // Min 10% so flat zeros still show a bump
            
            NSLayoutConstraint.activate([
                fillView.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
                fillView.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
                fillView.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
                fillView.heightAnchor.constraint(equalTo: barContainer.heightAnchor, multiplier: heightMultiplier)
            ])
            
            barChartStack.addArrangedSubview(barContainer)
        }
    }

    private func createStatCard(title: String, value: String) -> UIView {
        let v = UIView()
        v.backgroundColor = AppColors.cardBackground
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 1
        v.layer.borderColor = AppColors.cardBorder.cgColor

        let valLbl = UILabel()
        valLbl.text = value
        valLbl.font = .systemFont(ofSize: 20, weight: .bold)
        valLbl.textColor = AppColors.primary
        valLbl.textAlignment = .center
        valLbl.translatesAutoresizingMaskIntoConstraints = false

        let titLbl = UILabel()
        titLbl.text = title
        titLbl.font = .systemFont(ofSize: 12, weight: .medium)
        titLbl.textColor = .secondaryLabel
        titLbl.textAlignment = .center
        titLbl.translatesAutoresizingMaskIntoConstraints = false

        v.addSubview(valLbl)
        v.addSubview(titLbl)

        NSLayoutConstraint.activate([
            valLbl.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            valLbl.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -8),

            titLbl.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            titLbl.topAnchor.constraint(equalTo: valLbl.bottomAnchor, constant: 4),
            v.heightAnchor.constraint(equalToConstant: 72)
        ])

        return v
    }
}

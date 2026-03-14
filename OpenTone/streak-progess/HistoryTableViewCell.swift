
import UIKit

class HistoryTableViewCell: UITableViewCell {

    @IBOutlet weak var cardBackgroundView: UIView!
    @IBOutlet weak var iconImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var detailsLabel: UILabel!

    private let timestampLabel: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 11, weight: .medium)
        lbl.textColor = .tertiaryLabel
        lbl.textAlignment = .right
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let typeBadge: UILabel = {
        let lbl = UILabel()
        lbl.font = .systemFont(ofSize: 10, weight: .bold)
        lbl.textColor = AppColors.primary
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()

    private let iconContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.primary.withAlphaComponent(0.12)
        view.layer.cornerRadius = 20
        return view
    }()

    private let iconLabelView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = AppColors.primary
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.cardBackground
        view.layer.cornerRadius = 16
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.cardBorder.cgColor
        return view
    }()

    private let headlineLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 14, weight: .semibold)
        lbl.textColor = AppColors.textPrimary
        lbl.numberOfLines = 2
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }()

    private let topicLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 13, weight: .regular)
        lbl.textColor = .secondaryLabel
        lbl.numberOfLines = 2
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }()

    private let metaLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        lbl.textColor = .secondaryLabel
        return lbl
    }()

    private let continueIndicator: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "chevron.right")
        iv.tintColor = .tertiaryLabel
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private var didInstallModernLayout = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func awakeFromNib() {
        super.awakeFromNib()
    }

    private func commonInit() {
        applyTheme()
        installModernLayoutIfNeeded()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: HistoryTableViewCell, _) in
            self.applyTheme()
        }
    }

    private func applyTheme() {
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        cardView.backgroundColor = AppColors.cardBackground
        cardView.layer.borderColor = AppColors.cardBorder.cgColor
        iconContainerView.backgroundColor = AppColors.primary.withAlphaComponent(0.12)
        iconLabelView.tintColor = AppColors.primary
        headlineLabel.textColor = AppColors.textPrimary
        topicLabel.textColor = .secondaryLabel
        metaLabel.textColor = .secondaryLabel
    }

    private func installModernLayoutIfNeeded() {
        guard !didInstallModernLayout else { return }
        didInstallModernLayout = true

        // Remove fragile storyboard-driven views and their constraints.
        [cardBackgroundView, iconImageView, titleLabel, subtitleLabel, detailsLabel].forEach {
            $0?.removeFromSuperview()
        }

        contentView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconLabelView)
        contentView.addSubview(cardView)
        contentView.addSubview(typeBadge)

        [headlineLabel, topicLabel, metaLabel, timestampLabel, continueIndicator].forEach {
            cardView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            iconContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            iconContainerView.widthAnchor.constraint(equalToConstant: 40),
            iconContainerView.heightAnchor.constraint(equalToConstant: 40),

            iconLabelView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconLabelView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconLabelView.widthAnchor.constraint(equalToConstant: 24),
            iconLabelView.heightAnchor.constraint(equalToConstant: 24),

            typeBadge.topAnchor.constraint(equalTo: iconContainerView.bottomAnchor, constant: 6),
            typeBadge.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),

            cardView.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            timestampLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            timestampLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

            continueIndicator.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            continueIndicator.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            continueIndicator.widthAnchor.constraint(equalToConstant: 10),
            continueIndicator.heightAnchor.constraint(equalToConstant: 14),

            headlineLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            headlineLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            headlineLabel.trailingAnchor.constraint(lessThanOrEqualTo: timestampLabel.leadingAnchor, constant: -8),

            topicLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 8),
            topicLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            topicLabel.trailingAnchor.constraint(equalTo: continueIndicator.leadingAnchor, constant: -10),

            metaLabel.topAnchor.constraint(equalTo: topicLabel.bottomAnchor, constant: 8),
            metaLabel.leadingAnchor.constraint(equalTo: headlineLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: continueIndicator.leadingAnchor, constant: -10),
            metaLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with item: HistoryItem) {
        headlineLabel.text = item.title
        topicLabel.text = item.topic
        metaLabel.text = "⏱ \(item.duration)"
        iconLabelView.image = UIImage(systemName: item.iconName)
        iconLabelView.tintColor = AppColors.primary

        // Timestamp
        timestampLabel.text = item.timeString

        // Type badge
        if let type = item.activityType {
            typeBadge.isHidden = false
            switch type {
            case .jam:
                typeBadge.text = "JAM"
                typeBadge.textColor = AppColors.primary
            case .roleplay:
                typeBadge.text = "ROLEPLAY"
                typeBadge.textColor = .systemOrange
            case .aiCall:
                typeBadge.text = "AI Call"
                typeBadge.textColor = .systemOrange
            }
        } else {
            typeBadge.isHidden = true
        }

        // Show chevron for sessions that can open feedback details or resume roleplay.
        let opensFeedbackDetail = item.isCompleted && item.feedback != nil
        let canResumeRoleplay = item.scenarioId != nil
        continueIndicator.isHidden = !(opensFeedbackDetail || canResumeRoleplay)
    }
}
